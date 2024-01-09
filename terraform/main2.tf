
provider "aws" {
  region = var.aws_region
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

resource "aws_lambda_function" "ip_provider" {
  function_name    = "ipProvider"
  runtime          = "nodejs16.x"
  handler          = "lambda_function.handler"
  source_code_hash = filebase64sha256("lambda_function.js")
  filename         = "lambda_function.zip"
  role             = aws_iam_role.lambda_exec.arn
}

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

# API Gateway Setup
resource "aws_api_gateway_rest_api" "api" {
  name        = "IPProviderAPI"
  description = "API for IP Provider Lambda Function"
}

resource "aws_api_gateway_resource" "api_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "url"
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

# CloudFront Distribution with S3 and API Gateway as Origins
resource "aws_cloudfront_distribution" "s3_distribution" {
  enabled = true

  # Origin for S3 Bucket
  origin {
    domain_name = aws_s3_bucket.static_site.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.static_site.id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  # Origin for API Gateway
  origin {
#    domain_name = "${aws_api_gateway_rest_api.api.execution_arn}.execute-api.${var.aws_region}.amazonaws.com/v1"
#    origin_id   = "API-${aws_api_gateway_rest_api.api.id}"

    domain_name = "${aws_api_gateway_rest_api.api.id}.execute-api.${var.aws_region}.amazonaws.com"
    origin_id   = "API-${aws_api_gateway_rest_api.api.id}"
    origin_path = "/url"

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

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # Cache Behavior for API Gateway
  ordered_cache_behavior {
    path_pattern     = "/url/*"
    target_origin_id = "API-${aws_api_gateway_rest_api.api.id}"

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
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
  #  acl          = "public-read"
}
