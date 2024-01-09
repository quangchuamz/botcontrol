provider "aws" {
  region = var.aws_region
  alias = "main"
}

provider "aws" {
  region = "us-east-1"
  alias = "useast1"
}


# S3 Bucket for Static Content
resource "aws_s3_bucket" "static_site" {
  bucket = "my-static-site-bucket-300885"
  versioning {
    enabled = true
  }
}

# CloudFront Origin Access Identity for S3
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for ${aws_s3_bucket.static_site.bucket}"
}

# S3 Bucket Policy to allow only CloudFront
resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.static_site.bucket
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action   = "s3:GetObject",
      Effect   = "Allow",
      Resource = "${aws_s3_bucket.static_site.arn}/*",
      Principal = {
        AWS = "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity ${aws_cloudfront_origin_access_identity.oai.id}"
      }
    }]
  })
}

# Lambda Function Setup
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.js"
  output_path = "lambda_function.zip"
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
    }]
  })
}

# Attaching the AWSLambdaBasicExecutionRole policy to the Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "ip_provider" {
  function_name    = "ipProvider"
  runtime          = "nodejs16.x"
  handler          = "lambda_function.handler"
  source_code_hash = filebase64sha256("lambda_function.js")
  filename         = "lambda_function.zip"
  role             = aws_iam_role.lambda_exec.arn
}

# Permission for API Gateway to invoke the Lambda function
resource "aws_lambda_permission" "api_lambda_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ip_provider.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/GET/api"
}

# API Gateway Setup (Regional)
resource "aws_api_gateway_rest_api" "api" {
  name        = "IPProviderAPI"
  description = "API for IP Provider Lambda Function"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "api_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_method" "api_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.api_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.api_resource.id
  http_method             = aws_api_gateway_method.api_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.ip_provider.invoke_arn
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration
  ]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "v1"
}


# ... [CORS Configuration and Integration for API Gateway] ...

# Cache Policy (using a managed policy)
data "aws_cloudfront_cache_policy" "s3_managed_policy" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "apigw_managed_policy" {
  name = "Managed-CachingDisabled"
}
# Origin Request Policy (using a managed policy)
data "aws_cloudfront_origin_request_policy" "apigw_managed_policy" {
  name = "Managed-AllViewerExceptHostHeader"
}

# Web acl on waf for cloudfront
resource "aws_wafv2_web_acl" "web_acl" {
  provider = aws.useast1
  name        = "web-acl-for-cloudfront"
  scope       = "CLOUDFRONT"  # Use "CLOUDFRONT" for CloudFront distributions
  description = "Web ACL for CloudFront distribution"
  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesBotControlRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesBotControlRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "botControl"
      sampled_requests_enabled   = true
    }
  }

  # Custom Rule for Token Absent
  rule {
    name     = "TokenAbsentBlock"
    priority = 2

    action {
      block {}
    }

    statement {
      label_match_statement {
        key   = "awswaf:managed:token:absent"
        scope = "LABEL"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "TokenAbsentBlock"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "webACL"
    sampled_requests_enabled   = true
  }
}

# CloudFront Distribution with S3 and API Gateway as Origins
resource "aws_cloudfront_distribution" "s3_distribution" {
  enabled = true

  web_acl_id = aws_wafv2_web_acl.web_acl.arn //specify webacl id for cloudfront

  # Origin for S3 Bucket
  origin {
    domain_name = aws_s3_bucket.static_site.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.static_site.id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  # Origin for API Gateway (Regional)
  origin {
    domain_name = "${aws_api_gateway_rest_api.api.id}.execute-api.${var.aws_region}.amazonaws.com"
    origin_id   = "API-${aws_api_gateway_rest_api.api.id}"
    origin_path = "/v1"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_root_object = "index.html"

  # Default Cache Behavior (for S3 Bucket)
  default_cache_behavior {
    target_origin_id       = "S3-${aws_s3_bucket.static_site.id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]


#    The parameter ForwardedValues cannot be used when a cache policy is associated to the cache behavior.
#    forwarded_values {
#      query_string = false
#      cookies {
#        forward = "none"
#      }
#    }

    # Using the Cache Policy and Origin Request Policy
    cache_policy_id               = data.aws_cloudfront_cache_policy.s3_managed_policy.id
#    origin_request_policy_id      = data.aws_cloudfront_origin_request_policy.managed_policy.id
  }

  # Cache Behavior for API Gateway (Regional)
  ordered_cache_behavior {
    path_pattern     = "api"
    target_origin_id = "API-${aws_api_gateway_rest_api.api.id}"

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]

    # Using the Cache Policy and Origin Request Policy
    cache_policy_id               = data.aws_cloudfront_cache_policy.apigw_managed_policy.id
    origin_request_policy_id      = data.aws_cloudfront_origin_request_policy.apigw_managed_policy.id
  }

  # Viewer certificate using the CloudFront default certificate
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # Add restrictions block
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

## Upload index.html to the S3 Bucket
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.static_site.id
  key          = "index.html"
  source       = "index.html"
  content_type = "text/html"
}








