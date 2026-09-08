output "api_url" {
  description = "Base URL to submit a task"
  value       = "${aws_apigatewayv2_stage.default.invoke_url}task"
}

output "queue_url" {
  description = "URL of the SQS queue"
  value       = aws_sqs_queue.tasks.url
}

output "consumer_function_name" {
  description = "Name of the consumer Lambda function (for checking CloudWatch logs)"
  value       = aws_lambda_function.consumer.function_name
}
