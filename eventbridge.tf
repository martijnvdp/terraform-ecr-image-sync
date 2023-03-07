locals {

  event_rules = {
    ECRImageSyncScheduledEvent = {
      description         = var.lambda_function_settings.event_rules.scheduled_event.description
      is_enabled          = var.lambda_function_settings.event_rules.scheduled_event.is_enabled
      schedule_expression = var.lambda_function_settings.event_rules.scheduled_event.schedule_expression
    }
    ECRImageSyncUpdatedInputJson = {
      description   = var.lambda_function_settings.event_rules.payload_updated.description
      is_enabled    = var.lambda_function_settings.event_rules.payload_updated.is_enabled
      event_pattern = <<-EOF
      {
        "source": ["aws.events"],
        "detail-type": ["AWS API Call via CloudTrail"],
        "detail": {
          "eventName": ["PutTargets"],
          "eventSource": ["events.amazonaws.com"],
          "requestParameters": {
            "rule": ["ECRImageSyncScheduledEvent"]
          }
        }
      }
      EOF
    }
    ECRImageSyncChangedTagOnECRRepo = {
      description   = var.lambda_function_settings.event_rules.repository_tags.description
      is_enabled    = var.lambda_function_settings.event_rules.repository_tags.is_enabled
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
          resources = "$.resources"
        }
        input_template = <<EOF
        {
          "check_digest": ${local.sync_settings.check_digest},
          "max_results": ${local.sync_settings.max_results},
          "repositories": <resources>
        }
        EOF
      }
    }
  }
}

resource "aws_cloudwatch_event_rule" "trigger" {
  for_each = local.event_rules

  description         = each.value.description
  event_pattern       = try(each.value.event_pattern, null)
  is_enabled          = try(each.value.is_enabled, true)
  name                = each.key
  schedule_expression = try(each.value.schedule_expression, null)
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "trigger" {
  for_each = local.event_rules

  arn       = aws_lambda_function.ecr_image_sync.arn
  input     = try(each.value.input_transformer, {}) == {} ? jsonencode(local.sync_settings) : null
  rule      = aws_cloudwatch_event_rule.trigger[each.key].name
  target_id = var.lambda_function_settings.name

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
  function_name = var.lambda_function_settings.name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.trigger[each.key].arn
  statement_id  = "AllowExecutionFromEventBridge${each.key}"
}
