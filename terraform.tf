# Variables
variable "region" {}
variable "account_id" {}
variable "s3_bucket" {}
variable "lambda_name" {}

provider "aws" {
  region = "${var.region}"
}

# IAM Role and Policy
resource "aws_iam_role" "this" {
  name               = "${var.lambda_name}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": "PypiWebServerRole"
    }
  ]
}
EOF
}

data "aws_iam_policy_document" "this" {
  statement {
    actions   = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
    effect = "Allow"
  }
  statement {
    actions   = ["s3:*"]
    resources = [
      "arn:aws:s3:::${var.s3_bucket}",
      "arn:aws:s3:::${var.s3_bucket}/*"
    ]
    effect = "Allow"
  }
}

resource "aws_iam_policy" "this" {
  name = "${var.lambda_name}"
  path = "/"
  description = "IAM policy PyPi Lambda Web Server"
  policy = data.aws_iam_policy_document.this.json
}

resource "aws_iam_role_policy_attachment" "pypi" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name = "${var.lambda_name}_api"
  binary_media_types = [
    "application/zip",
    "application/octet-stream",
    "*/*"
  ]
}

resource "aws_api_gateway_resource" "api_resource" {
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  parent_id   = "${aws_api_gateway_rest_api.api.root_resource_id}"
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "method" {
  rest_api_id   = "${aws_api_gateway_rest_api.api.id}"
  resource_id   = "${aws_api_gateway_resource.api_resource.id}"
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = "${aws_api_gateway_rest_api.api.id}"
  resource_id             = "${aws_api_gateway_resource.api_resource.id}"
  http_method             = "${aws_api_gateway_method.method.http_method}"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.lambda.arn}/invocations"
}

# Lambda
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.lambda.arn}"
  principal     = "apigateway.amazonaws.com"

  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:aws:execute-api:${var.region}:${var.account_id}:${aws_api_gateway_rest_api.api.id}/*/${aws_api_gateway_method.method.http_method}/{proxy+}"
}

resource "aws_lambda_function" "lambda" {
  filename         = "lambda.zip"
  function_name    = "${var.lambda_name}"
  role             = "${aws_iam_role.this.arn}"
  handler          = "lambda.handler"
  runtime          = "python3.6"
  source_code_hash = "${filebase64sha256("lambda.zip")}"

  environment {
    variables = {
      S3_BUCKET = "${var.s3_bucket}"
    }
  }
}



