data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_kms_alias" "s3" {
  name = "alias/aws/s3"
}

data "aws_s3_bucket" "existing" {
  count  = var.create_bucket ? 0 : 1
  bucket = var.s3_bucket
}

locals {
  bucket_name = var.create_bucket ? module.lambda_bucket[0].name : data.aws_s3_bucket.existing[0].id
  bucket_arn  = var.create_bucket ? module.lambda_bucket[0].arn : data.aws_s3_bucket.existing[0].arn
}

module "lambda_bucket" {
  count         = var.create_bucket ? 1 : 0
  source        = "github.com/schubergphilis/terraform-aws-mcaf-s3?ref=v0.1.10"
  name          = var.s3_bucket
  tags          = var.tags
  versioning    = true
  force_destroy = true
  kms_key_id    = data.aws_kms_alias.s3.target_key_arn
}

resource "aws_lambda_function" "lambda_function" {
  function_name    = var.lambda_function_name
  handler          = "main"
  runtime          = "go1.x"
  role             = aws_iam_role.lambda_assume_role.arn
  filename         = "${path.module}/dist/main.zip"
  source_code_hash = filebase64sha256("${path.module}/dist/main.zip")
  timeout          = 820
  tags             = var.tags

  environment {
    variables = {
      IMAGES         = jsonencode(var.docker_images)
      REGION         = data.aws_region.current.name
      BUCKET_NAME    = local.bucket_name
      AWS_ACCOUNT_ID = data.aws_caller_identity.current.account_id
    }
  }
}

resource "aws_cloudwatch_event_rule" "event_rule" {
  name                = var.schedule.name
  description         = var.schedule.description
  schedule_expression = var.schedule.expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "event_check" {
  rule      = aws_cloudwatch_event_rule.event_rule.name
  target_id = "ecr-image-sync"
  arn       = aws_lambda_function.lambda_function.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_lambda" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.id
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.event_rule.arn
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
    type  = "LOCAL"
    modes = ["LOCAL_SOURCE_CACHE"]
  }

  environment {
    compute_type    = "BUILD_GENERAL1_MEDIUM"
    image           = "aws/codebuild/standard:2.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "AWS_REGION"
      value = data.aws_region.current.name
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/buildspec.yml")
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
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      output_artifacts = ["source"]

      configuration = {
        S3Bucket             = local.bucket_name
        PollForSourceChanges = "true"
        S3ObjectKey          = "images.zip"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name            = "Build"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source"]
      version         = "1"

      configuration = {
        ProjectName = aws_codebuild_project.ecr_pull_push.name
      }
    }
  }
}

