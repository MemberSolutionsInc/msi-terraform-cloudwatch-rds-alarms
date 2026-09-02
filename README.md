# msi-terraform-cloudwatch-rds-alarms

Tiered (info/ticket/critical) CloudWatch alarms for RDS instances — CPU utilization, CPU credit
balance, freeable memory, free storage space, and database connections.

Generalized from member-solutions' original `rds-alarms/main.tf`, which alarmed on a fixed set
of hand-written instances directly. This module keeps the exact same tiering model and alarm
logic, but takes the instance list and thresholds as input so any account can reuse it.

## Why three tiers, not two

Unlike the EC2/ALB-focused `msi-terraform-cloudwatch-alarms` (warn/crit), RDS alarms here use
three tiers:

- `info` — visibility only, never pages. Trend/heads-up.
- `ticket` — act during business hours. Saturation building, pre-impact.
- `critical` — act now, user impact likely. Pages on-call.

Any tier can be omitted per metric per instance — e.g. `cpu_credit_balance` only makes sense on
burstable instance classes, and `free_storage_percent` should be left `null` for Aurora instances
(no per-instance `FreeStorageSpace` metric on the shared, auto-scaling cluster volume).

## Usage

```hcl
module "rds_alarms" {
  source = "git::https://github.com/MemberSolutionsInc/msi-terraform-cloudwatch-rds-alarms.git?ref=v0.1.0"

  instances = {
    my-postgres-db = {
      allocated_storage_gb  = 100
      instance_memory_bytes = 17179869184 # 16 GiB

      cpu_percent = {
        info     = 70
        ticket   = 80
        critical = 95
      }

      freeable_memory_percent = {
        info     = 20
        ticket   = 10
        critical = 5
      }

      free_storage_percent = {
        info     = 30
        ticket   = 20
        critical = 10
      }

      database_connections = {
        info     = 1261
        ticket   = 1441
        critical = 1621
      }

      # Omit cpu_credit_balance entirely for a non-burstable instance class.
    }

    my-aurora-mysql = {
      allocated_storage_gb  = null # Aurora: no per-instance FreeStorageSpace metric
      instance_memory_bytes = 2147483648

      cpu_percent = {
        info     = 70
        ticket   = 85
        critical = 95
      }

      cpu_credit_balance = {
        info     = 144
        ticket   = 58
        critical = 10
      }

      freeable_memory_percent = {
        info     = 20
        ticket   = 10
        critical = 5
      }

      free_storage_percent = null

      database_connections = {
        info     = 31
        ticket   = 35
        critical = 40
      }
    }
  }

  sns_topic_arns = {
    info     = "arn:aws:sns:us-east-1:123456789012:aws-cw-info"
    ticket   = "arn:aws:sns:us-east-1:123456789012:aws-cw-warning"
    critical = "arn:aws:sns:us-east-1:123456789012:aws-cw-critical"
  }

  tags = {
    service  = "rds-alarms"
    env      = "production"
    severity = "warning" # overridden per-alarm to match its tier
    team     = "infrastructure"
    runbook  = "https://runbooks.membersolutions.com/rds-alarms"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `instances` | Map of RDS instances to alarm on, keyed by DB instance identifier. See variable description for the full per-metric tier shape. | `map(object({...}))` | n/a | yes |
| `sns_topic_arns` | SNS topic ARNs by tier (`info`, `ticket`, `critical`). | `object({ info = string, ticket = string, critical = string })` | n/a | yes |
| `tags` | Mandatory tagging convention shared across this observability module family. Must include `service`, `env`, `severity`, `team`, `runbook`. `severity` is overridden per-alarm to match its tier (`ticket` maps to `"warning"`). | `map(string)` | n/a | yes |
| `period_seconds` | Evaluation window (seconds) for every metric. | `number` | `300` | no |
| `evaluation_periods` | Number of consecutive windows evaluated. | `number` | `3` | no |
| `datapoints_to_alarm_cpu` | Datapoints required to alarm on CPU utilization. | `number` | `3` | no |
| `datapoints_to_alarm_default` | Datapoints required to alarm on storage/memory/connections/credit-balance metrics. | `number` | `2` | no |

## Outputs

| Name | Description |
|------|-------------|
| `alarm_arns` | Map of every alarm ARN, keyed by `<metric>.<instance>-<tier>`. |
| `alarm_names` | Map of every alarm name, keyed by `<metric>.<instance>-<tier>` — feed into `msi-terraform-cloudwatch-composite-alarms`' `alarm_names` input. |

## Requirements

| Name | Version |
|------|---------|
| terraform | `~> 1.0` |
| aws | `~> 5.0` |
