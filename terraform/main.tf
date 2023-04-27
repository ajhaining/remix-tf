//----------------------------------------------------------------------------//
//                                  Helpers                                   //
//----------------------------------------------------------------------------//

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

//----------------------------------------------------------------------------//
//                                   Locals                                   //
//----------------------------------------------------------------------------//

locals {
  security_header_name = "X-SPW-Origin-Verify"
}

//----------------------------------------------------------------------------//
//                               Remix SSR API                                //
//----------------------------------------------------------------------------//

// API Gateway

resource "aws_api_gateway_rest_api" "remix_ssr" {
  name = var.application_name

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

// API Gateway Deployment

resource "aws_api_gateway_deployment" "remix_ssr" {
  rest_api_id = aws_api_gateway_rest_api.remix_ssr.id

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

// API Gateway Stage

resource "aws_api_gateway_stage" "remix_ssr" {
  deployment_id = aws_api_gateway_deployment.remix_ssr.id
  rest_api_id   = aws_api_gateway_rest_api.remix_ssr.id
  stage_name    = "main"
}

// API Gateway Web ACL

// Creates a Web ACL that can be attached to the API Gateway. The Web ACL will
// block requests that do not contain the security header that is sent by the
// Cloudfront Distribution. This prevents a malicious user from bypassing
// Cloudfront by sending requests directly to the API Gateway Directly.

resource "aws_wafv2_web_acl" "remix_ssr" {
  name  = "${var.application_name}-remix-ssr"
  scope = "REGIONAL"

  default_action {
    block {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "RemixSsrWebAcl"
    sampled_requests_enabled   = true
  }

  rule {
    name     = "${var.application_name}-remix-ssr-security-header"
    priority = 0

    action {
      allow {}
    }

    statement {
      byte_match_statement {
        field_to_match {
          single_header {
            name = lower(local.security_header_name)
          }
        }

        positional_constraint = "EXACTLY"
        search_string         = random_password.security_header.result

        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RemixSsrSecurityHeader"
      sampled_requests_enabled   = true
    }
  }
}

// API Gateway Web ACL Association

resource "aws_wafv2_web_acl_association" "remix_ssr" {
  resource_arn = aws_api_gateway_stage.remix_ssr.arn
  web_acl_arn  = aws_wafv2_web_acl.remix_ssr.arn
}

// Route Mappings

// ANY /

resource "aws_api_gateway_method" "root" {
  authorization = "NONE"
  http_method   = "ANY"
  resource_id   = aws_api_gateway_rest_api.remix_ssr.root_resource_id
  rest_api_id   = aws_api_gateway_rest_api.remix_ssr.id
}

resource "aws_api_gateway_integration" "root" {
  rest_api_id             = aws_api_gateway_rest_api.remix_ssr.id
  resource_id             = aws_api_gateway_rest_api.remix_ssr.root_resource_id
  http_method             = aws_api_gateway_method.root.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.remix_ssr.invoke_arn
}

// ANY /{proxy+}

resource "aws_api_gateway_resource" "proxy" {
  parent_id   = aws_api_gateway_rest_api.remix_ssr.root_resource_id
  path_part   = "{proxy+}"
  rest_api_id = aws_api_gateway_rest_api.remix_ssr.id
}

resource "aws_api_gateway_method" "proxy" {
  authorization = "NONE"
  http_method   = "ANY"
  resource_id   = aws_api_gateway_resource.proxy.id
  rest_api_id   = aws_api_gateway_rest_api.remix_ssr.id
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.remix_ssr.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.remix_ssr.invoke_arn
}

//----------------------------------------------------------------------------//
//                             Remix SSR Function                             //
//----------------------------------------------------------------------------//

// Package

// This will be moved out into CI pipeline to allow artifact to be built outside
// of Terraform

data "archive_file" "remix_ssr" {
  type        = "zip"
  source_dir  = "${path.module}/../build/server"
  output_path = "${path.module}/../build/server.zip"
}

// Lambda Function

resource "aws_lambda_function" "remix_ssr" {
  filename         = data.archive_file.remix_ssr.output_path
  function_name    = "${var.application_name}-remix-ssr"
  handler          = "index.handler"
  memory_size      = 1152
  role             = aws_iam_role.remix_ssr.arn
  runtime          = "nodejs18.x"
  timeout          = 10
  source_code_hash = data.archive_file.remix_ssr.output_base64sha256

  environment {
    variables = {
      EXAMPLE_SECRET_ARN = aws_secretsmanager_secret.example.arn
      EXAMPLE_RUNTIME_VAR = "Injected in main.tf"
    }
  }

  ephemeral_storage {
    size = 512
  }

  # vpc_config {
  #   security_group_ids = []
  #   subnet_ids         = []
  # }
}

// Lambda Function Permissions

resource "aws_lambda_permission" "remix_ssr" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remix_ssr.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.remix_ssr.id}/*/*/*"
}

// Lambda Function Execution Role

resource "aws_iam_role" "remix_ssr" {
  name = "${var.application_name}-remix-ssr"

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
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    # "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  ]

  inline_policy {
    name = "get-example-secret"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = "secretsmanager:GetSecretValue"
          Resource = aws_secretsmanager_secret.example.arn
        }
      ]
    })
  }
}

// Lambda Function Logs

resource "aws_cloudwatch_log_group" "remix_ssr" {
  name = "/aws/lambda/${aws_lambda_function.remix_ssr.function_name}"
}

//----------------------------------------------------------------------------//
//                               Static Assets                                //
//----------------------------------------------------------------------------//

// Stores the Static Assets for the website, and sets up a permissions that
// allow only the Cloudfront Distribution to access.

// Bucket

resource "aws_s3_bucket" "static_assets" {
  bucket = "${var.application_name}-static-assets"
}

// Bucket Policy

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
          "AWS:SourceArn" = aws_cloudfront_distribution.distribution.arn
        }
      }
    }
  })
}

//----------------------------------------------------------------------------//
//                          Cloudfront Distribution                           //
//----------------------------------------------------------------------------//

// Handles routing of requests to the Remix SSR API or the Static Assets
// Bucket. Also enables caching of Static Assets, but doesn't cache Dynamic
// Rendered Content by default, although it can cache the response if caching
// headers are set.

// Distribution

resource "aws_cloudfront_distribution" "distribution" {
  comment             = "${var.application_name}-distribution"
  enabled             = true
  default_root_object = ""
  is_ipv6_enabled     = true
  price_class         = "PriceClass_100"
  wait_for_deployment = true
  web_acl_id          = aws_wafv2_web_acl.distribution.arn

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  // Remix SSR Origin

  origin {
    domain_name = "${aws_api_gateway_rest_api.remix_ssr.id}.execute-api.${data.aws_region.current.name}.amazonaws.com"
    origin_path = "/${aws_api_gateway_stage.remix_ssr.stage_name}"
    origin_id   = "remix-ssr"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = local.security_header_name
      value = random_password.security_header.result
    }
  }

  // Remix SSR Behavior

  default_cache_behavior {
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    target_origin_id         = "remix-ssr"
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = aws_cloudfront_cache_policy.caching_enabled_off_by_default.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id
  }

  // Static Assets Origin

  origin {
    domain_name              = aws_s3_bucket.static_assets.bucket_regional_domain_name
    origin_id                = "static-assets"
    origin_access_control_id = aws_cloudfront_origin_access_control.distribution.id
  }

  // Failover Origin (Static -> Remix SSR)

  origin_group {
    origin_id = "failover"

    failover_criteria {
      status_codes = [404, 403]
    }

    member {
      origin_id = "static-assets"
    }

    member {
      origin_id = "remix-ssr"
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
  }
}

// Distribution Origin Access Control

resource "aws_cloudfront_origin_access_control" "distribution" {
  name                              = "${var.application_name}-distribution"
  description                       = "Cloudfront Distribution access to Static Assets"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

// Distribution Origin Request Policy (Managed - All Viewer Except Host Header)

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host_header" {
  name = "Managed-AllViewerExceptHostHeader"
}

// Distribution Cache Policy (Custom - Caching Enabled Off By Default)

resource "aws_cloudfront_cache_policy" "caching_enabled_off_by_default" {
  name        = "${var.application_name}-caching-enabled-off-by-default"
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

// Distribution Cache Policy (Managed - Caching Optimized)

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

// Distribution Extended Monitoring Subscription

resource "aws_cloudfront_monitoring_subscription" "distribution" {
  distribution_id = aws_cloudfront_distribution.distribution.id

  monitoring_subscription {
    realtime_metrics_subscription_config {
      realtime_metrics_subscription_status = "Enabled"
    }
  }
}

// Distribution Web ACL

resource "aws_wafv2_web_acl" "distribution" {
  provider = aws.global

  name  = "${var.application_name}-distribution"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "DistributionWebAcl"
    sampled_requests_enabled   = true
  }

  // Core Rule Set (AWS Managed)

  // AWS Managed Core Rule Set rule group contains rules that are generally
  // applicable to web applications. This provides protection against
  // exploitation of a wide range of vulnerabilities, including some of the high
  // risk and commonly occurring vulnerabilities described in OWASP publications
  // such as OWASP Top 10. Consider using this rule group for any AWS WAF use
  // case.

  // See other AWS Managed Rule Sets here:
  // https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html

  rule {
    name     = "${var.application_name}-distribution-common-rule-set"
    priority = 10

    override_action {
      count {} # Just adds counts for this rule, change to 'none' to block.
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "DistributionWebAclCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }
}

//----------------------------------------------------------------------------//
//                              Security Header                               //
//----------------------------------------------------------------------------//

// Security Header Value

resource "random_password" "security_header" {
  special = false
  length  = 50

  keepers = {
    header_name = local.security_header_name
  }
}

//----------------------------------------------------------------------------//
//                           Example Runtime Secret                           //
//----------------------------------------------------------------------------//

resource "aws_secretsmanager_secret" "example" {
  name                    = "${var.application_name}-example"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "example" {
  secret_id = aws_secretsmanager_secret.example.id
  secret_string = "s£kr3t v4lU3!"
}

//----------------------------------------------------------------------------//
//                         Upload Static Assets to S3                         //
//----------------------------------------------------------------------------//

// This will be moved out into CI pipeline to allow artifacts to be built
// outside of Terraform and uploaded without destroying old assets

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