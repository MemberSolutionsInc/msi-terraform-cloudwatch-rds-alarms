output "alarm_arns" {
  description = "Map of every CloudWatch alarm ARN created by this module, keyed by <metric>.<instance>-<tier>."
  value = merge(
    { for k, v in aws_cloudwatch_metric_alarm.cpu_utilization : "cpu_utilization.${k}" => v.arn },
    { for k, v in aws_cloudwatch_metric_alarm.free_storage_space : "free_storage_space.${k}" => v.arn },
    { for k, v in aws_cloudwatch_metric_alarm.freeable_memory : "freeable_memory.${k}" => v.arn },
    { for k, v in aws_cloudwatch_metric_alarm.database_connections : "database_connections.${k}" => v.arn },
    { for k, v in aws_cloudwatch_metric_alarm.cpu_credit_balance : "cpu_credit_balance.${k}" => v.arn },
  )
}

output "alarm_names" {
  description = "Map of every CloudWatch alarm name created by this module, keyed by <metric>.<instance>-<tier> - useful as input to msi-terraform-cloudwatch-composite-alarms."
  value = merge(
    { for k, v in aws_cloudwatch_metric_alarm.cpu_utilization : "cpu_utilization.${k}" => v.alarm_name },
    { for k, v in aws_cloudwatch_metric_alarm.free_storage_space : "free_storage_space.${k}" => v.alarm_name },
    { for k, v in aws_cloudwatch_metric_alarm.freeable_memory : "freeable_memory.${k}" => v.alarm_name },
    { for k, v in aws_cloudwatch_metric_alarm.database_connections : "database_connections.${k}" => v.alarm_name },
    { for k, v in aws_cloudwatch_metric_alarm.cpu_credit_balance : "cpu_credit_balance.${k}" => v.alarm_name },
  )
}
