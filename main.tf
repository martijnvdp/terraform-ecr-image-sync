locals {
  bucket_arn           = local.create_bucket ? module.lambda_bucket[0].arn : var.s3_workflow.enabled ? data.aws_s3_bucket.existing[0].arn : ""
  bucket_name          = local.create_bucket ? module.lambda_bucket[0].name : var.s3_workflow.enabled ? data.aws_s3_bucket.existing[0].id : ""
  create_bucket        = var.s3_workflow.create_bucket && var.s3_workflow.enabled
  create_secret        = var.docker_hub_credentials != null && var.s3_workflow.enabled
  docker_hub_cred_name = local.create_secret ? "${random_id.aws_sm_item[0].keepers.name}${random_id.aws_sm_item[0].id}" : ""

  settings = {
    check_digest = var.lambda.settings.check_digest
    max_results  = var.lambda.settings.max_results
  }

  lambda_zip = try("${path.module}/${[for f in fileset(path.module, "${var.lambda.function_zip_file_folder}/*.zip") : f][0]}", "no zip file in dist")
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_kms_alias" "s3" {
  name = "alias/aws/s3"
}

data "aws_s3_bucket" "existing" {
  count = !local.create_bucket && var.s3_workflow.enabled ? 1 : 0

  bucket = var.s3_workflow.bucket
}

module "lambda_bucket" {
  count = local.create_bucket ? 1 : 0

  force_destroy = true
  kms_key_arn   = data.aws_kms_alias.s3.target_key_arn
  name          = "${var.s3_workflow.bucket}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  source        = "github.com/schubergphilis/terraform-aws-mcaf-s3?ref=v0.6.2"
  tags          = var.tags
  versioning    = true

  lifecycle_rule = [
    {
      id      = "retention"
      enabled = true

      abort_incomplete_multipart_upload = {
        days_after_initiation = 1
      }

      expiration = {
        days = 7
      }

      noncurrent_version_expiration = {
        noncurrent_days = 14
      }
    }
  ]
}

resource "aws_lambda_function" "ecr_image_sync" {
  filename         = var.lambda.container_uri == null ? local.lambda_zip : null
  function_name    = var.lambda.name
  handler          = var.lambda.container_uri == null ? "main" : null
  image_uri        = var.lambda.container_uri == null ? null : var.lambda.container_uri
  package_type     = var.lambda.container_uri == null ? "Zip" : "Image"
  role             = aws_iam_role.lambda_assume_role.arn
  runtime          = var.lambda.container_uri == null ? "go1.x" : null
  source_code_hash = var.lambda.container_uri == null ? filebase64sha256(local.lambda_zip) : null
  tags             = var.tags
  timeout          = 600

  environment {
    variables = local.create_bucket ? {
      AWS_ACCOUNT_ID  = data.aws_caller_identity.current.account_id
      BUCKET_NAME     = local.bucket_name
      DOCKER_PASSWORD = var.docker_hub_credentials != null ? jsondecode(var.docker_hub_credentials).password : null
      DOCKER_USERNAME = var.docker_hub_credentials != null ? jsondecode(var.docker_hub_credentials).username : null
      REGION          = data.aws_region.current.name
      } : {
      AWS_ACCOUNT_ID  = data.aws_caller_identity.current.account_id
      DOCKER_PASSWORD = var.docker_hub_credentials != null ? jsondecode(var.docker_hub_credentials).password : null
      DOCKER_USERNAME = var.docker_hub_credentials != null ? jsondecode(var.docker_hub_credentials).username : null
      REGION          = data.aws_region.current.name
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_codebuild_project" "ecr_pull_push" {
  count = var.s3_workflow.enabled ? 1 : 0

  build_timeout = "60"
  name          = var.s3_workflow.codebuild_project_name
  service_role  = aws_iam_role.codebuild_assume_role[0].arn
  tags          = var.tags

  artifacts {
    type = "CODEPIPELINE"
  }

  cache {
    modes = ["LOCAL_SOURCE_CACHE"]
    type  = "LOCAL"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:5.0"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "AWS_REGION"
      value = data.aws_region.current.name
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    dynamic "environment_variable" {
      for_each = var.s3_workflow.debug ? [var.s3_workflow.debug] : []
      content {
        name  = "LOGGING"
        value = "debug"
      }
    }
  }

  source {
    buildspec = length(aws_secretsmanager_secret_version.docker_hub_credentials[*].arn) > 0 ? templatefile("${path.module}/buildspec.yml", {
      secret_options = "shell: bash\n  secrets-manager:\n    DOCKER_HUB_USERNAME: ${tostring(aws_secretsmanager_secret.docker_hub_credentials[0].id)}:username\n    DOCKER_HUB_PASSWORD: ${tostring(aws_secretsmanager_secret.docker_hub_credentials[0].id)}:password"
      crane_version  = var.s3_workflow.crane_version
      }) : templatefile("${path.module}/buildspec.yml", {
      secret_options = "shell: bash"
      crane_version  = var.s3_workflow.crane_version
    })
    type = "CODEPIPELINE"
  }
}

resource "aws_codepipeline" "pl_ecr_pull_push" {
  count = var.s3_workflow.enabled ? 1 : 0

  name     = var.s3_workflow.codepipeline_name
  role_arn = aws_iam_role.codepipeline_assume_role[0].arn
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
        ProjectName = aws_codebuild_project.ecr_pull_push[0].name
      }
    }
  }
}

resource "random_id" "aws_sm_item" {
  count = local.create_secret ? 1 : 0

  byte_length = 4

  keepers = {
    name = var.docker_hub_credentials_sm_item_name
  }
}

// tfsec:ignore:AWS095 - TODO: CCV-1403
resource "aws_secretsmanager_secret" "docker_hub_credentials" {
  count = local.create_secret ? 1 : 0

  name = local.docker_hub_cred_name
}

// tfsec:ignore:GEN003
resource "aws_secretsmanager_secret_version" "docker_hub_credentials" {
  count = local.create_secret ? 1 : 0

  secret_id     = aws_secretsmanager_secret.docker_hub_credentials[0].id
  secret_string = var.docker_hub_credentials
}
