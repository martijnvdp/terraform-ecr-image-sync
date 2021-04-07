locals {
  bucket_arn  = var.create_bucket ? module.lambda_bucket[0].arn : data.aws_s3_bucket.existing[0].arn
  bucket_name = var.create_bucket ? module.lambda_bucket[0].name : data.aws_s3_bucket.existing[0].id
  images = flatten([
    for k, v in var.docker_images : [{
      image_name   = k
      repo_prefix  = try(v.repo_prefix, var.docker_images_defaults.repo_prefix)
      include_tags = try(v.include_tags, var.docker_images_defaults.include_tags)
      exclude_tags = try(v.exclude_tags, var.docker_images_defaults.exclude_tags)
      }
    ]
  ])
  lambda_zip = "${path.module}/${[for f in fileset(path.module, "dist/*.zip") : f][0]}"
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
  filename         = local.lambda_zip
  handler          = "main"
  role             = aws_iam_role.lambda_assume_role.arn
  runtime          = "go1.x"
  source_code_hash = filebase64sha256(local.lambda_zip)
  tags             = var.tags

  environment {
    variables = {
      AWS_ACCOUNT_ID = data.aws_caller_identity.current.account_id
      BUCKET_NAME    = local.bucket_name
      IMAGES         = jsonencode(local.images)
      REGION         = data.aws_region.current.name
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
    compute_type    = "BUILD_GENERAL1_MEDIUM"
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
  }

  source {
    buildspec = file("${path.module}/buildspec.yml")
    type      = "CODEPIPELINE"
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
