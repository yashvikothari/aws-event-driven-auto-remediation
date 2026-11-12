output "target_security_group_id" {
  description = "Unattached demo security group"
  value       = aws_security_group.test_sg.id
}
output "lambda_function_name" {
  description = "Remediation Lambda function"
  value       = aws_lambda_function.remediator.function_name
}
output "dynamodb_audit_table" {
  description = "Write-once application audit receipts"
  value       = aws_dynamodb_table.audit_ledger.name
}
output "config_rule_name" {
  description = "Managed AWS Config SSH compliance rule"
  value       = aws_config_config_rule.restricted_ssh.name
}
