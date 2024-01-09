
provider "aws" {
  region = var.aws_region
}

# S3 Bucket for Static Content (without ACL specification)
resource "aws_s3_bucket" "static_site" {
  bucket = "my-static-site-bucket-300885"
  versioning {
    enabled = true
  }
}

# CloudFront Origin Access Identity
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for ${aws_s3_bucket.static_site.bucket}"
}

# S3 Bucket Policy to allow only CloudFront
resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.static_site.bucket
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "s3:GetObject",
      Effect    = "Allow",
      Resource  = "${aws_s3_bucket.static_site.arn}/*",
      Principal = {
        AWS = "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity ${aws_cloudfront_origin_access_identity.oai.id}"
      }
    }]
  })
}

# CloudFront Distribution with OAI
resource "aws_cloudfront_distribution" "s3_distribution" {
  enabled = true  # Enable the CloudFront distribution

  origin {
    domain_name = aws_s3_bucket.static_site.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.static_site.id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  default_root_object = "index.html"

  # Default cache behavior
  default_cache_behavior {
    target_origin_id = "S3-${aws_s3_bucket.static_site.id}"

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
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

  # The configuration for viewer_certificate, cache_behaviors,
  # price_class, etc., as per your requirements

  # More configurations as needed...
}



# Lambda Function, IAM Role for Lambda, API Gateway configurations remain the same.

# Data source to zip the Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.js"
  output_path = "lambda_function.zip"
}

# Lambda Function
resource "aws_lambda_function" "ip_provider" {
  function_name = "ipProvider"
  runtime       = "nodejs16.x"
  handler       = "lambda_function.handler"

  # Assuming lambda_function.js is in the same directory as your Terraform configuration
  source_code_hash = filebase64sha256("lambda_function.js")
  filename         = "lambda_function.zip"

  role = aws_iam_role.lambda_exec.arn
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

# API Gateway
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
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.api_resource.id
  http_method = aws_api_gateway_method.api_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.ip_provider.invoke_arn
}

## Upload index.html to the S3 Bucket
resource "aws_s3_object" "my_file" {
  bucket = aws_s3_bucket.static_site.id
  key    = "index.html"  # The name that the file will have in the bucket
  source = "index.html"  # Path to the file on your local machine
  content_type = "text/html"

  # Optional: If you want to make the file publicly readable (not recommended for sensitive data)
  # acl = "public-read"
}



