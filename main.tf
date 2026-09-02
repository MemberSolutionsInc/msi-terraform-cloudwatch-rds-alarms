# Tiered (info/ticket/critical) CloudWatch alarms for RDS instances.
# Generalized from member-solutions' original rds-alarms/main.tf - see
# that account's vars.yaml for the reasoning behind per-metric tiering
# (burstable-credit exceptions, SQL Server memory exception, Aurora
# storage exception, etc.), which callers reproduce via var.instances.

locals {
  # "ticket" (this module's middle tier name) maps to this org's "warning"
  # severity vocabulary used elsewhere (msi-terraform-cloudwatch-alarms,
  # msi-terraform-cloudwatch-composite-alarms) - kept as "ticket" in the
  # tier name/alarm name for continuity with the original member-solutions
  # rds-alarms alarm names, but mapped for the tags.severity value.
  tier_severity = {
    info     = "info"
    ticket   = "warning"
    critical = "critical"
  }

  tier_topic_arn = {
    info     = var.sns_topic_arns.info
    ticket   = var.sns_topic_arns.ticket
    critical = var.sns_topic_arns.critical
  }

  # Flatten instance x severity-tier into one map per metric, keyed by
  # "<instance>-<tier>", so each metric below is a single for_each
  # resource regardless of how many tiers a given instance defines for it.
  #
  # Every per-tier attribute is `optional(number)` on an object type, and
  # Terraform's object type conversion backfills an omitted optional
  # attribute as an explicit `null` (it does not just leave the key
  # missing) - confirmed live: an instance that only sets `info`/`ticket`
  # for cpu_credit_balance still produces a `critical = null` entry when
  # iterated over. Every `for` below filters those out explicitly
  # (`if val != null`); without this, a null threshold value reaches the
  # alarm resource's string interpolation and fails at plan/apply time.

  cpu_alarms = merge([
    for name, inst in var.instances : {
      for tier, pct in inst.cpu_percent : "${name}-${tier}" => {
        instance = name
        tier     = tier
        percent  = pct
      } if pct != null
    }
  ]...)

  free_storage_space_alarms = merge([
    for name, inst in var.instances : {
      for tier, pct in coalesce(inst.free_storage_percent, {}) : "${name}-${tier}" => {
        instance = name
        tier     = tier
        bytes    = inst.allocated_storage_gb * 1073741824 * pct / 100
      } if pct != null
    }
  ]...)

  freeable_memory_alarms = merge([
    for name, inst in var.instances : {
      for tier, pct in inst.freeable_memory_percent : "${name}-${tier}" => {
        instance = name
        tier     = tier
        bytes    = inst.instance_memory_bytes * pct / 100
      } if pct != null
    }
  ]...)

  database_connections_alarms = merge([
    for name, inst in var.instances : {
      for tier, count in inst.database_connections : "${name}-${tier}" => {
        instance = name
        tier     = tier
        count    = count
      } if count != null
    }
  ]...)

  cpu_credit_balance_alarms = merge([
    for name, inst in var.instances : {
      for tier, credits in inst.cpu_credit_balance : "${name}-${tier}" => {
        instance = name
        tier     = tier
        credits  = credits
      } if credits != null
    }
  ]...)
}

resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  for_each = local.cpu_alarms

  alarm_name          = "rds-${each.value.instance}-cpu_utilization-${each.value.tier}"
  alarm_description   = "CPU utilization for RDS instance ${each.value.instance} exceeds ${each.value.percent}% (${each.value.tier})."
  comparison_operator = "GreaterThanThreshold"
  threshold           = each.value.percent

  namespace   = "AWS/RDS"
  metric_name = "CPUUtilization"
  statistic   = "Average"

  period              = var.period_seconds
  evaluation_periods  = var.evaluation_periods
  datapoints_to_alarm = var.datapoints_to_alarm_cpu

  dimensions = {
    DBInstanceIdentifier = each.value.instance
  }

  alarm_actions = [local.tier_topic_arn[each.value.tier]]
  ok_actions    = [local.tier_topic_arn[each.value.tier]]

  tags = merge(var.tags, { severity = local.tier_severity[each.value.tier] }, { Name = "rds-${each.value.instance}-cpu_utilization-${each.value.tier}" })
}

resource "aws_cloudwatch_metric_alarm" "free_storage_space" {
  for_each = local.free_storage_space_alarms

  alarm_name          = "rds-${each.value.instance}-free_storage_space-${each.value.tier}"
  alarm_description   = "Free storage space for RDS instance ${each.value.instance} is below ${each.value.bytes} bytes (${each.value.tier})."
  comparison_operator = "LessThanThreshold"
  threshold           = each.value.bytes

  namespace   = "AWS/RDS"
  metric_name = "FreeStorageSpace"
  statistic   = "Average"

  period              = var.period_seconds
  evaluation_periods  = var.evaluation_periods
  datapoints_to_alarm = var.datapoints_to_alarm_default

  dimensions = {
    DBInstanceIdentifier = each.value.instance
  }

  alarm_actions = [local.tier_topic_arn[each.value.tier]]
  ok_actions    = [local.tier_topic_arn[each.value.tier]]

  tags = merge(var.tags, { severity = local.tier_severity[each.value.tier] }, { Name = "rds-${each.value.instance}-free_storage_space-${each.value.tier}" })
}

resource "aws_cloudwatch_metric_alarm" "freeable_memory" {
  for_each = local.freeable_memory_alarms

  alarm_name          = "rds-${each.value.instance}-freeable_memory-${each.value.tier}"
  alarm_description   = "Freeable memory for RDS instance ${each.value.instance} is below ${each.value.bytes} bytes (${each.value.tier})."
  comparison_operator = "LessThanThreshold"
  threshold           = each.value.bytes

  namespace   = "AWS/RDS"
  metric_name = "FreeableMemory"
  statistic   = "Average"

  period              = var.period_seconds
  evaluation_periods  = var.evaluation_periods
  datapoints_to_alarm = var.datapoints_to_alarm_default

  dimensions = {
    DBInstanceIdentifier = each.value.instance
  }

  alarm_actions = [local.tier_topic_arn[each.value.tier]]
  ok_actions    = [local.tier_topic_arn[each.value.tier]]

  tags = merge(var.tags, { severity = local.tier_severity[each.value.tier] }, { Name = "rds-${each.value.instance}-freeable_memory-${each.value.tier}" })
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  for_each = local.database_connections_alarms

  alarm_name          = "rds-${each.value.instance}-database_connections-${each.value.tier}"
  alarm_description   = "Database connections for RDS instance ${each.value.instance} exceed ${each.value.count} (${each.value.tier})."
  comparison_operator = "GreaterThanThreshold"
  threshold           = each.value.count

  namespace   = "AWS/RDS"
  metric_name = "DatabaseConnections"
  statistic   = "Average"

  period              = var.period_seconds
  evaluation_periods  = var.evaluation_periods
  datapoints_to_alarm = var.datapoints_to_alarm_default

  dimensions = {
    DBInstanceIdentifier = each.value.instance
  }

  alarm_actions = [local.tier_topic_arn[each.value.tier]]
  ok_actions    = [local.tier_topic_arn[each.value.tier]]

  tags = merge(var.tags, { severity = local.tier_severity[each.value.tier] }, { Name = "rds-${each.value.instance}-database_connections-${each.value.tier}" })
}

resource "aws_cloudwatch_metric_alarm" "cpu_credit_balance" {
  for_each = local.cpu_credit_balance_alarms

  alarm_name        = "rds-${each.value.instance}-cpu_credit_balance-${each.value.tier}"
  alarm_description = "CPU credit balance for RDS instance ${each.value.instance} is at or below ${each.value.credits} (${each.value.tier})."
  # A balance can't go negative, so a plain "less than 0" critical
  # threshold would never actually fire - use <= for that tier.
  comparison_operator = each.value.credits == 0 ? "LessThanOrEqualToThreshold" : "LessThanThreshold"
  threshold           = each.value.credits

  namespace   = "AWS/RDS"
  metric_name = "CPUCreditBalance"
  statistic   = "Average"

  period              = var.period_seconds
  evaluation_periods  = var.evaluation_periods
  datapoints_to_alarm = var.datapoints_to_alarm_default

  dimensions = {
    DBInstanceIdentifier = each.value.instance
  }

  alarm_actions = [local.tier_topic_arn[each.value.tier]]
  ok_actions    = [local.tier_topic_arn[each.value.tier]]

  tags = merge(var.tags, { severity = local.tier_severity[each.value.tier] }, { Name = "rds-${each.value.instance}-cpu_credit_balance-${each.value.tier}" })
}
