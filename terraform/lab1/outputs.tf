# Output for S3 Bucket Name
output "s3_bucket_name" {
  value = aws_s3_bucket.static_site.bucket
  description = "The name of the S3 bucket used for static site hosting."
}

# Output for CloudFront Distribution Domain Name
output "cloudfront_distribution_domain" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
  description = "The domain name of the CloudFront distribution."
}

# Output for API Gateway URL
output "api_gateway_url" {
  value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.aws_region}.amazonaws.com/v1/api"
  description = "The URL endpoint for the API Gateway."
}
