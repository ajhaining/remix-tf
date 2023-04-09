//----------------------------------------------------------------------------//
//                                  Helpers                                   //
//----------------------------------------------------------------------------//

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

//----------------------------------------------------------------------------//
//                           Dynamic Rendering API                            //
//----------------------------------------------------------------------------//

// Routes requests to the Dynamic Rendering Function.

// API Gateway

resource "aws_api_gateway_rest_api" "dynamic_rendering" {
  name = "dynamic_rendering"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_deployment" "dynamic_rendering" {
  rest_api_id = aws_api_gateway_rest_api.dynamic_rendering.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.root.id,
      aws_api_gateway_integration.root.id,

      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.proxy.id,
      aws_api_gateway_integration.proxy.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "dynamic_rendering" {
  deployment_id = aws_api_gateway_deployment.dynamic_rendering.id
  rest_api_id   = aws_api_gateway_rest_api.dynamic_rendering.id
  stage_name    = "main"
}

// Route Mappings

// ANY /

resource "aws_api_gateway_method" "root" {
  authorization = "NONE"
  http_method   = "ANY"
  resource_id   = aws_api_gateway_rest_api.dynamic_rendering.root_resource_id
  rest_api_id   = aws_api_gateway_rest_api.dynamic_rendering.id
}

resource "aws_api_gateway_integration" "root" {
  rest_api_id             = aws_api_gateway_rest_api.dynamic_rendering.id
  resource_id             = aws_api_gateway_rest_api.dynamic_rendering.root_resource_id
  http_method             = aws_api_gateway_method.root.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.dynamic_rendering.invoke_arn
}

// ANY /{proxy+}

resource "aws_api_gateway_resource" "proxy" {
  parent_id   = aws_api_gateway_rest_api.dynamic_rendering.root_resource_id
  path_part   = "{proxy+}"
  rest_api_id = aws_api_gateway_rest_api.dynamic_rendering.id
}

resource "aws_api_gateway_method" "proxy" {
  authorization = "NONE"
  http_method   = "ANY"
  resource_id   = aws_api_gateway_resource.proxy.id
  rest_api_id   = aws_api_gateway_rest_api.dynamic_rendering.id
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.dynamic_rendering.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.dynamic_rendering.invoke_arn
}

//----------------------------------------------------------------------------//
//                         Dynamic Rendering Function                         //
//----------------------------------------------------------------------------//

// Packages the Dynamic Rendering Function and deploys it to AWS Lambda.

// Package

data "archive_file" "dynamic_rendering" {
  type        = "zip"
  source_dir  = "${path.module}/../build/server"
  output_path = "${path.module}/../build/server.zip"
}

// Function

resource "aws_lambda_function" "dynamic_rendering" {
  filename         = data.archive_file.dynamic_rendering.output_path
  function_name    = "dynamic_rendering"
  handler          = "index.handler"
  memory_size      = 1152
  role             = aws_iam_role.dynamic_rendering.arn
  runtime          = "nodejs18.x"
  timeout          = 5
  source_code_hash = data.archive_file.dynamic_rendering.output_base64sha256

  ephemeral_storage {
    size = 512
  }
}

// Function Permissions

resource "aws_lambda_permission" "dynamic_rendering" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dynamic_rendering.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.dynamic_rendering.id}/*/*/*"
}

resource "aws_iam_role" "dynamic_rendering" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  ]
}

// Log Group

resource "aws_cloudwatch_log_group" "dynamic_rendering" {
  name = "/aws/lambda/${aws_lambda_function.dynamic_rendering.function_name}"
}

//----------------------------------------------------------------------------//
//                               Static Assets                                //
//----------------------------------------------------------------------------//

// Stores the Static Assets for the website, and sets up a permissions that
// allow only the CDN to access.

// Bucket

resource "aws_s3_bucket" "static_assets" {
  force_destroy = true
}

// Bucket Permissions

resource "aws_s3_bucket_acl" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id
  acl    = "private"
}

resource "aws_cloudfront_origin_access_control" "static_assets" {
  name                              = "static_assets"
  description                       = "Cloudfront Distribution access to Static Assets"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = {
      Effect = "Allow",
      Principal = {
        Service = "cloudfront.amazonaws.com"
      },
      Action   = "s3:GetObject",
      Resource = "${aws_s3_bucket.static_assets.arn}/*",
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
        }
      }
    }
  })
}

//----------------------------------------------------------------------------//
//                                    CDN                                     //
//----------------------------------------------------------------------------//

// Handles routing of requests to the Dynamic Rendering API or the Static Assets
// Bucket. Also enables caching of Static Assets, but doesn't cache Dynamic
// Rendered Content by default, although it can cache the response if caching
// headers are set.

// CDN

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = ""
  web_acl_id          = aws_wafv2_web_acl.cdn_web_acl.arn

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  // Dynamic Rendering Origin

  origin {
    domain_name = "${aws_api_gateway_rest_api.dynamic_rendering.id}.execute-api.${data.aws_region.current.name}.amazonaws.com"
    origin_path = "/${aws_api_gateway_stage.dynamic_rendering.stage_name}"
    origin_id   = "dynamic-rendering"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = local.custom_header_name
      value = random_password.custom_header.result
    }
  }

  // Dynamic Rendering Behavior

  default_cache_behavior {
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "dynamic-rendering"
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = aws_cloudfront_cache_policy.caching_enabled_off_by_default.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id
    compress                 = true
  }

  // Static Assets Origin

  origin {
    domain_name              = aws_s3_bucket.static_assets.bucket_regional_domain_name
    origin_id                = "static-assets"
    origin_access_control_id = aws_cloudfront_origin_access_control.static_assets.id
  }

  // Failover Origin (Static -> Dynamic Rendering)

  origin_group {
    origin_id = "failover"

    failover_criteria {
      status_codes = [404]
    }

    member {
      origin_id = "static-assets"
    }

    member {
      origin_id = "dynamic-rendering"
    }
  }

  // Static Assets Behavior

  ordered_cache_behavior {
    path_pattern           = "/_static/*"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    target_origin_id       = "failover"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true
  }
}

// Origin Request Policies

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host_header" {
  name = "Managed-AllViewerExceptHostHeader"
}

// Cache Policies

resource "aws_cloudfront_cache_policy" "caching_enabled_off_by_default" {
  name        = "Custom-CachingEnabledOffByDefault"
  comment     = "Caching enabled but turned off by default"
  default_ttl = 0
  min_ttl     = 0
  max_ttl     = 31536000

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

// CDN Web ACL

resource "aws_wafv2_web_acl" "cdn_web_acl" {
  provider = aws.global

  name  = "cdn-web-acl"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "CdnWebAclAllowed"
    sampled_requests_enabled   = true
  }
}

//----------------------------------------------------------------------------//
//                                API Firewall                                //
//----------------------------------------------------------------------------//

// Creates a Web ACL that can be attached to an API Gateway. The Web ACL will
// block requests that do not contain a custom header that is sent by the CDN.
// This prevents a malicious user from sending requests directly to the Dynamic
// Rendering API bypassing the CDN.

// Locals

locals {
  custom_header_name = "X-Origin-Verify"
}

// Random Header Value

resource "random_password" "custom_header" {
  special = false
  length  = 50

  keepers = {
    header_name = local.custom_header_name
  }
}

// Security Header Secret

resource "aws_secretsmanager_secret" "custom_header" {
  name                    = "custom-header"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "custom_header" {
  secret_id     = aws_secretsmanager_secret.custom_header.id
  secret_string = random_password.custom_header.result
}

// API Web ACL

resource "aws_wafv2_web_acl" "api_web_acl" {
  name  = "api-web-acl"
  scope = "REGIONAL"

  default_action {
    block {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "ApiWebAclBlocked"
    sampled_requests_enabled   = true
  }

  rule {
    name     = "only-cloudfront-requests"
    priority = 0

    action {
      allow {}
    }

    statement {
      byte_match_statement {
        field_to_match {
          single_header {
            name = lower(local.custom_header_name)
          }
        }

        positional_constraint = "EXACTLY"
        search_string         = random_password.custom_header.result

        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ApiWebAclAllowed"
      sampled_requests_enabled   = true
    }
  }
}

resource "aws_wafv2_web_acl_association" "api_web_acl" {
  resource_arn = aws_api_gateway_stage.dynamic_rendering.arn
  web_acl_arn  = aws_wafv2_web_acl.api_web_acl.arn
}

//----------------------------------------------------------------------------//
//                         Upload Static Assets to S3                         //
//----------------------------------------------------------------------------//

// Reads the Static Assets directories and returns a map of files. The map is
// used to upload the files to S3. This method of uploading files removes any
// old files, so it may not be desirable where you want old and new files to
// coexist.

// Read Static Assets

module "assets" {
  source   = "hashicorp/dir/template"
  base_dir = "${path.module}/../build/assets"
}

// Upload Static Assets

resource "aws_s3_object" "assets" {
  for_each = module.assets.files

  bucket        = aws_s3_bucket.static_assets.id
  key           = each.key
  content_type  = each.value.content_type
  source        = each.value.source_path
  etag          = each.value.digests.md5
  cache_control = "public,max-age=31536000,immutable"
}

// Read Public Assets

module "public" {
  source   = "hashicorp/dir/template"
  base_dir = "${path.module}/../public"
}

// Upload Public Assets

resource "aws_s3_object" "public" {
  for_each = module.public.files

  bucket        = aws_s3_bucket.static_assets.id
  key           = each.key
  content_type  = each.value.content_type
  source        = each.value.source_path
  etag          = each.value.digests.md5
  cache_control = "public, max-age=3600, s-max-age=86400"
}

//----------------------------------------------------------------------------//
//                                  Outputs                                   //
//----------------------------------------------------------------------------//

output "cloudfront" {
  value = "https://${aws_cloudfront_distribution.cdn.domain_name}"
}
