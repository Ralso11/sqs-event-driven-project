# --- Package both Lambda functions into zip files automatically ---

data "archive_file" "producer_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/producer/handler.py"
  output_path = "${path.module}/producer.zip"
}

data "archive_file" "consumer_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/consumer/handler.py"
  output_path = "${path.module}/consumer.zip"
}

# --- The SQS queue itself ---

resource "aws_sqs_queue" "tasks" {
  name                       = "${var.project_name}-${var.environment}-tasks"
  visibility_timeout_seconds = 30
}

# --- IAM role for the producer function ---

resource "aws_iam_role" "producer_exec" {
  name = "${var.project_name}-producer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "producer_logs" {
  role       = aws_iam_role.producer_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "producer_sqs_send" {
  name = "${var.project_name}-producer-sqs-send"
  role = aws_iam_role.producer_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.tasks.arn
      }
    ]
  })
}

# --- IAM role for the consumer function ---

resource "aws_iam_role" "consumer_exec" {
  name = "${var.project_name}-consumer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "consumer_logs" {
  role       = aws_iam_role.consumer_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "consumer_sqs_receive" {
  name = "${var.project_name}-consumer-sqs-receive"
  role = aws_iam_role.consumer_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.tasks.arn
      }
    ]
  })
}

# --- The producer Lambda function ---

resource "aws_lambda_function" "producer" {
  function_name    = "${var.project_name}-${var.environment}-producer"
  filename         = data.archive_file.producer_zip.output_path
  source_code_hash = data.archive_file.producer_zip.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.producer_exec.arn

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.tasks.url
    }
  }
}

# --- The consumer Lambda function ---

resource "aws_lambda_function" "consumer" {
  function_name    = "${var.project_name}-${var.environment}-consumer"
  filename         = data.archive_file.consumer_zip.output_path
  source_code_hash = data.archive_file.consumer_zip.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.12"
  role             = aws_iam_role.consumer_exec.arn
}

# --- Event source mapping: connects the queue to the consumer automatically ---

resource "aws_lambda_event_source_mapping" "sqs_to_consumer" {
  event_source_arn = aws_sqs_queue.tasks.arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 1
}

# --- API Gateway, connected ONLY to the producer ---

resource "aws_apigatewayv2_api" "tasks" {
  name          = "${var.project_name}-${var.environment}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "producer" {
  api_id                 = aws_apigatewayv2_api.tasks.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.producer.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_task" {
  api_id    = aws_apigatewayv2_api.tasks.id
  route_key = "POST /task"
  target    = "integrations/${aws_apigatewayv2_integration.producer.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.tasks.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.tasks.execution_arn}/*/*"
}
