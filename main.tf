locals {
  bucket_arn  = var.create_bucket ? aws_s3_bucket.lambda_bucket[0].arn : data.aws_s3_bucket.existing[0].arn
  bucket_name = var.create_bucket ? aws_s3_bucket.lambda_bucket[0].id : data.aws_s3_bucket.existing[0].id
  images = flatten([
    for k, v in var.docker_images : [{
      image_name   = k
      repo_prefix  = try(v.repo_prefix, var.docker_images_defaults.repo_prefix)
      include_tags = try(v.include_tags, var.docker_images_defaults.include_tags)
      exclude_tags = try(v.exclude_tags, var.docker_images_defaults.exclude_tags)
      }
    ]
  ])
  lambda_zip = try("${path.module}/${[for f in fileset(path.module, "${var.lambda_function_zipfile_folder}/*.zip") : f][0]}", "no zip file in dist")
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

resource "aws_s3_bucket" "lambda_bucket" {
  count         = var.create_bucket ? 1 : 0
  acl           = "private"
  bucket        = "${var.s3_bucket}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  force_destroy = true
  tags          = var.tags

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = data.aws_kms_alias.s3.target_key_arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  versioning {
    enabled = true
  }

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
  tags             = var.tags

  environment {
    variables = {
      AWS_ACCOUNT_ID = data.aws_caller_identity.current.account_id
      BUCKET_NAME    = local.bucket_name
      IMAGES         = jsonencode(local.images)
      REGION         = data.aws_region.current.name
      REPO_PREFIX    = var.default_repo_prefix
    }
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
  rule      = aws_cloudwatch_event_rule.event_rule.name
  target_id = "ecr-image-sync"
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_lambda" {
  function_name = aws_lambda_function.lambda_function.id
  action        = "lambda:InvokeFunction"
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
    image           = "aws/codebuild/standard:2.0"
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
    buildspec = var.dockerhub_credentials_sm != null ? templatefile("${path.module}/buildspec.yml", {
      secret_options = "shell: bash\n  secrets-manager:\n    DOCKER_HUB_USERNAME: ${var.dockerhub_credentials_sm}:username\n    DOCKER_HUB_PASSWORD: ${var.dockerhub_credentials_sm}:password"
      }) : var.dockerhub_credentials_ssm.username_item != null ? templatefile("${path.module}/buildspec.yml", {
      secret_options = "shell: bash\n  parameter-store:\n    DOCKER_HUB_USERNAME: ${var.dockerhub_credentials_ssm.username_item}\n    DOCKER_HUB_PASSWORD: ${var.dockerhub_credentials_ssm.password_item}"
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
