//----------------------------------------------------------------------------//
//                                  Outputs                                   //
//----------------------------------------------------------------------------//

output "distribution_url" {
  value = "https://${aws_cloudfront_distribution.distribution.domain_name}"
}

output "api_url" {
  value = aws_api_gateway_stage.remix_ssr.invoke_url
}
