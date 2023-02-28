locals {
  scheduled_event_name = "ECRImageSyncScheduledEvent"

  event_rules = {
    ECRImageSyncRepoCreatedRule = {
      description   = "Capture each ECR repository created event"
      event_pattern = <<-EOF
      {
        "source": ["aws.ecr"],
        "detail-type": ["AWS API Call via CloudTrail"],
        "detail": {
          "eventName": ["CreateRepository"],
          "eventSource": ["ecr.amazonaws.com"]
        }
      }
      EOF
    }
    "${local.scheduled_event_name}" = {
      description         = "CloudWatch schedule for synchronization of the public Docker images."
      schedule_expression = var.schedule_expression
    }
    ECRImageSyncUpdatedInputJson = {
      description   = "Capture all updated input JSON events: ${local.scheduled_event_name}"
      event_pattern = <<-EOF
      {
        "source": ["aws.events"],
        "detail-type": ["AWS API Call via CloudTrail"],
        "detail": {
          "eventName": ["PutTargets"],
          "eventSource": ["events.amazonaws.com"],
          "requestParameters": {
            "rule": ["${local.scheduled_event_name}"]
          }
        }
      }
      EOF
    }
    ECRImageSyncChangedTagOnECRRepo = {
      description   = "Capture each ECR repository tag changed event"
      event_pattern = <<-EOF
      {
        "source": ["aws.tag"],
        "detail-type": ["Tag Change on Resource"],
        "detail": {
          "changed-tag-keys": [
            "ecr_sync_include_rls",
            "ecr_sync_include_tags",
            "ecr_sync_opt",
            "ecr_sync_release_only",
            "ecr_sync_source",
            "ecr_sync_constraint"
          ]
        }
      }
      EOF
      input_transformer = {
        input_paths = {
          resource = "$.resources[0]"
        }
        input_template = <<EOF
        {
          "check_digest": ${local.settings.check_digest},
          "ecr_repo_prefix": "${local.settings.ecr_repo_prefix}",
          "event_resource": <resource>,
          "max_results": ${local.settings.max_results}
        }
        EOF
      }
    }
  }
}

resource "aws_cloudwatch_event_rule" "trigger" {
  for_each = local.event_rules

  name                = each.key
  event_pattern       = try(each.value.event_pattern, null)
  schedule_expression = try(each.value.schedule_expression, null)
  description         = each.value.description
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "trigger" {
  for_each = local.event_rules

  arn       = aws_lambda_function.ecr_image_sync.arn
  input     = try(each.value.input_transformer, {}) == {} ? jsonencode(local.settings) : null
  rule      = aws_cloudwatch_event_rule.trigger[each.key].name
  target_id = var.lambda_function_name

  dynamic "input_transformer" {
    for_each = try(each.value.input_transformer, {}) != {} ? [1] : []
    content {
      input_paths    = each.value.input_transformer.input_paths
      input_template = each.value.input_transformer.input_template
    }
  }
}

resource "aws_lambda_permission" "trigger" {
  for_each = local.event_rules

  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "events.amazonaws.com"
  statement_id  = "AllowExecutionFromEventBridge${each.key}"
  source_arn    = aws_cloudwatch_event_rule.trigger[each.key].arn
}
