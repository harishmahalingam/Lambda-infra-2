resource "aws_ecr_repository" "example" {
  name = "service-repo"
}

data "aws_iam_policy_document" "ecr_policy" {
  statement {
    sid    = "AllowPushPull"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::583174075212:user/Test-user"]
    }
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:GetAuthorizationToken",
    ]
  }
}

resource "aws_ecr_repository_policy" "example" {
  repository = aws_ecr_repository.example.name
  policy     = data.aws_iam_policy_document.ecr_policy.json
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Principal = {
Service = "lambda.amazonaws.com"
      }
      Effect = "Allow"
      Sid    = ""
    }]
  })
}
 
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
role = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
 
# Lambda using container image
resource "aws_lambda_function" "my_lambda" {
  function_name = "my-container-lambda"
  role          = aws_iam_role.lambda_exec_role.arn
  package_type  = "Image"
  image_uri     = "583174075212.dkr.ecr.us-east-1.amazonaws.com/service-repo:latest"
  timeout       = 10
}
 
# Create HTTP API Gateway
resource "aws_apigatewayv2_api" "http_api" {
  name          = "lambda-http-api"
  protocol_type = "HTTP"
}
 
# Integration between API Gateway and Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
api_id = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.my_lambda.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}
 
# Create route
resource "aws_apigatewayv2_route" "default_route" {
api_id = aws_apigatewayv2_api.http_api.id
  route_key = "GET /"
target = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}
 
# Create stage
resource "aws_apigatewayv2_stage" "default_stage" {
api_id = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}
 
# Grant API Gateway permission to invoke Lambda
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_lambda.function_name
principal = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
