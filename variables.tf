variable "instances" {
  description = <<-EOT
    Map of RDS instances to alarm on, keyed by DB instance identifier
    (the AWS/RDS DBInstanceIdentifier dimension value).

    Each metric carries up to three optional tiers instead of one:
      info     - visibility only, never pages. Trend/heads-up.
      ticket   - act during business hours. Saturation building, pre-impact.
      critical - act now, user impact likely. Pages on-call.
    Omit a tier (or the whole metric block) to skip that alarm entirely -
    e.g. burstable-only `cpu_credit_balance` on a non-burstable instance
    class, or `free_storage_percent = null` on an Aurora instance (no
    per-instance FreeStorageSpace metric on the shared cluster volume).

    `allocated_storage_gb` and `instance_memory_bytes` are the raw inputs
    this module derives absolute byte thresholds from for
    `free_storage_percent`/`freeable_memory_percent` - both percent-based
    inputs, since "X% of this instance's storage/memory" is what's
    actually meaningful across different instance classes, not a fixed
    byte count. Leave `allocated_storage_gb` null for Aurora (no
    per-instance storage metric to alarm on).
  EOT
  type = map(object({
    allocated_storage_gb  = optional(number)
    instance_memory_bytes = number

    cpu_percent = optional(object({
      info     = optional(number)
      ticket   = optional(number)
      critical = optional(number)
    }), {})

    cpu_credit_balance = optional(object({
      info     = optional(number)
      ticket   = optional(number)
      critical = optional(number)
    }), {})

    freeable_memory_percent = optional(object({
      info     = optional(number)
      ticket   = optional(number)
      critical = optional(number)
    }), {})

    free_storage_percent = optional(object({
      info     = optional(number)
      ticket   = optional(number)
      critical = optional(number)
    }))

    database_connections = optional(object({
      info     = optional(number)
      ticket   = optional(number)
      critical = optional(number)
    }), {})
  }))
}

variable "sns_topic_arns" {
  description = "SNS topic ARNs used for alarm notification (ALARM/OK) actions, by tier."
  type = object({
    info     = string
    ticket   = string
    critical = string
  })
}

variable "tags" {
  description = <<-EOT
    Mandatory tags applied to every alarm created by this module. Must
    contain non-empty values for: service, env, severity, team, runbook.

    `severity` is overridden per-alarm to "info", "warning", or "critical"
    to match that alarm's tier ("ticket" tier maps to "warning", matching
    this org's alert-severity vocabulary elsewhere).
  EOT
  type        = map(string)

  validation {
    condition = alltrue([
      for k in ["service", "env", "severity", "team", "runbook"] :
      contains(keys(var.tags), k) && trimspace(lookup(var.tags, k, "")) != ""
    ])
    error_message = "var.tags must include non-empty values for: service, env, severity, team, runbook."
  }
}

###############################################################################
# Threshold configuration - shared across all instances/tiers
###############################################################################

variable "period_seconds" {
  description = "Window (seconds) over which each metric is evaluated."
  type        = number
  default     = 300
}

variable "evaluation_periods" {
  description = "Number of consecutive windows a metric is evaluated over before alarming."
  type        = number
  default     = 3
}

variable "datapoints_to_alarm_cpu" {
  description = "Datapoints (out of evaluation_periods) required to alarm on CPU utilization - sustained for the full window by default."
  type        = number
  default     = 3
}

variable "datapoints_to_alarm_default" {
  description = "Datapoints (out of evaluation_periods) required to alarm on storage/memory/connections/credit-balance metrics."
  type        = number
  default     = 2
}
