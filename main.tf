locals {
  bucket_arn           = var.create_bucket ? module.lambda_bucket[0].arn : data.aws_s3_bucket.existing[0].arn
  bucket_name          = var.create_bucket ? module.lambda_bucket[0].name : data.aws_s3_bucket.existing[0].id
  docker_hub_cred_name = "${random_id.aws_sm_item[0].keepers.name}${random_id.aws_sm_item[0].id}"

  input_images_map = {
    check_digest          = try(var.lambda_function_settings.check_digest, false)
    ecr_repo_prefix       = try(var.lambda_function_settings.ecr_repo_prefix, "")
    images                = var.docker_images
    max_results           = try(var.lambda_function_settings.max_results, 0)
    slack_channel_id      = try(var.lambda_function_settings.slack_channel_id, "")
    slack_errors_only     = try(var.lambda_function_settings.slack_errors_only, false)
    slack_err_msg_subject = try(var.lambda_function_settings.slack_err_msg_subject, "ERROR - Executing the lambda `ecr-image-sync` in ${var.environment}:")
    slack_msg_header      = try(var.lambda_function_settings.slack_msg_header, "The following images are now synced to ECR:")
    slack_msg_subject     = try(var.lambda_function_settings.slack_err_msg_subject, "INFO - The lambda function `ecr-image-sync` has completed for ${var.environment}")
  }

  lambda_zip = try("${path.module}/${[for f in fileset(path.module, "${var.lambda_function_zip_file_folder}/*.zip") : f][0]}", "no zip file in dist")
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_kms_alias" "s3" {
  name = "alias/aws/s3"
}

data "aws_s3_bucket" "existing" {
  count  = var.create_bucket ? 0 : 1
  bucket = var.s3_bucket
}

module "lambda_bucket" {
  count         = var.create_bucket ? 1 : 0
  source        = "github.com/schubergphilis/terraform-aws-mcaf-s3?ref=v0.1.10"
  name          = "${var.s3_bucket}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  force_destroy = true
  kms_key_id    = data.aws_kms_alias.s3.target_key_arn
  versioning    = true
  tags          = var.tags
}

resource "aws_lambda_function" "lambda_function" {
  function_name    = var.lambda_function_name
  filename         = var.lambda_function_container_uri == null ? local.lambda_zip : null
  handler          = var.lambda_function_container_uri == null ? "main" : null
  image_uri        = var.lambda_function_container_uri == null ? null : var.lambda_function_container_uri
  package_type     = var.lambda_function_container_uri == null ? "Zip" : "Image"
  role             = aws_iam_role.lambda_assume_role.arn
  runtime          = var.lambda_function_container_uri == null ? "go1.x" : null
  source_code_hash = var.lambda_function_container_uri == null ? filebase64sha256(local.lambda_zip) : null
  timeout          = 600
  tags             = var.tags

  environment {
    variables = {
      AWS_ACCOUNT_ID    = data.aws_caller_identity.current.account_id
      BUCKET_NAME       = local.bucket_name
      REGION            = data.aws_region.current.name
      SLACK_OAUTH_TOKEN = var.slack_oauth_token
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_cloudwatch_event_rule" "event_rule" {
  name                = "ecr-images-sync-schedule"
  description         = "Synchronization cloudwatch schedule of the public docker images."
  schedule_expression = var.schedule_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "event_check" {
  arn       = aws_lambda_function.lambda_function.arn
  input     = jsonencode(local.input_images_map)
  rule      = aws_cloudwatch_event_rule.event_rule.name
  target_id = "ecr-image-sync"
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_lambda" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.id
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.event_rule.arn
  statement_id  = "AllowExecutionFromCloudWatch"
}

resource "aws_codebuild_project" "ecr_pull_push" {
  name          = var.codebuild_project_name
  build_timeout = "60"
  service_role  = aws_iam_role.codebuild_assume_role.arn
  tags          = var.tags

  artifacts {
    type = "CODEPIPELINE"
  }

  cache {
    modes = ["LOCAL_SOURCE_CACHE"]
    type  = "LOCAL"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:4.0"
    privileged_mode = true
    type            = "LINUX_CONTAINER"

    environment_variable {
      name  = "AWS_REGION"
      value = data.aws_region.current.name
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    dynamic "environment_variable" {
      for_each = var.debug ? [var.debug] : []
      content {
        name  = "LOGGING"
        value = "debug"
      }
    }
  }

  source {
    buildspec = length(aws_secretsmanager_secret_version.docker_hub_credentials[*].arn) > 0 ? templatefile("${path.module}/buildspec.yml", {
      secret_options = "shell: bash\n  secrets-manager:\n    DOCKER_HUB_USERNAME: ${tostring(aws_secretsmanager_secret.docker_hub_credentials[0].id)}:username\n    DOCKER_HUB_PASSWORD: ${tostring(aws_secretsmanager_secret.docker_hub_credentials[0].id)}:password"
      }) : templatefile("${path.module}/buildspec.yml", {
      secret_options = "shell: bash"
    })
    type = "CODEPIPELINE"
  }
}

resource "aws_codepipeline" "pl_ecr_pull_push" {
  name     = var.codepipeline_name
  role_arn = aws_iam_role.codepipeline_assume_role.arn
  tags     = var.tags

  artifact_store {
    location = local.bucket_name
    type     = "S3"

    encryption_key {
      id   = data.aws_kms_alias.s3.target_key_arn
      type = "KMS"
    }
  }

  stage {
    name = "Source"

    action {
      category         = "Source"
      name             = "Source"
      output_artifacts = ["source"]
      owner            = "AWS"
      provider         = "S3"
      version          = "1"

      configuration = {
        PollForSourceChanges = "true"
        S3Bucket             = local.bucket_name
        S3ObjectKey          = "images.zip"
      }
    }
  }

  stage {
    name = "Build"

    action {
      category        = "Build"
      input_artifacts = ["source"]
      name            = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"

      configuration = {
        ProjectName = aws_codebuild_project.ecr_pull_push.name
      }
    }
  }
}

resource "random_id" "aws_sm_item" {
  count       = var.docker_hub_credentials != null ? 1 : 0
  byte_length = 4

  keepers = {
    name = var.docker_hub_credentials_sm_item_name
  }
}

resource "aws_secretsmanager_secret" "docker_hub_credentials" {
  count = var.docker_hub_credentials != null ? 1 : 0
  name  = local.docker_hub_cred_name
}

resource "aws_secretsmanager_secret_version" "docker_hub_credentials" {
  count         = var.docker_hub_credentials != null ? 1 : 0
  secret_id     = aws_secretsmanager_secret.docker_hub_credentials[0].id
  secret_string = var.docker_hub_credentials
}
