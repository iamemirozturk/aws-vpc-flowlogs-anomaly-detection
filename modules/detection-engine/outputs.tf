output "sns_topic_arn"       { value = aws_sns_topic.alerts.arn }
output "lambda_function_name" { value = aws_lambda_function.detector.function_name }
output "lambda_function_arn"  { value = aws_lambda_function.detector.arn }
