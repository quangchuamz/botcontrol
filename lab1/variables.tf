variable "aws_region" {
  description = "The AWS region to deploy the resources."
  type        = string
  default     = "ap-southeast-1"
}

variable "s3_bucket_name" {
  description = "The name of the S3 bucket for the static site."
  type        = string
  default     = "my-static-site-bucket"
}

variable "lambda_function_name" {
  description = "The name of the Lambda function."
  type        = string
  default     = "ipProvider"
}

variable "lambda_runtime" {
  description = "The runtime environment for the Lambda function."
  type        = string
  default     = "nodejs16.x"
}

variable "api_gateway_name" {
  description = "The name of the API Gateway."
  type        = string
  default     = "IPProviderAPI"
}

variable "api_gateway_resource_path_part" {
  description = "The path part for the API Gateway resource."
  type        = string
  default     = "url"
}
