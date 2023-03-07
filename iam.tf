locals {
  bucket_arn              = local.create_bucket ? module.lambda_bucket[0].arn : var.s3_workflow.enabled ? data.aws_s3_bucket.existing[0].arn : ""
  ecr_repository_prefixes = var.ecr_repository_prefixes != null ? distinct(var.ecr_repository_prefixes) : null
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }
  }
}

#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "lambda" {
  statement {
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.lambda_function_settings.name}*", ]

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
  }

  statement {
    resources = ["arn:aws:xray:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}*", ]

    actions = [
      "xray:GetSamplingRules",
      "xray:GetSamplingStatisticSummaries",
      "xray:GetSamplingTargets",
      "xray:PutTelemetryRecords",
      "xray:PutTraceSegments"
    ]
  }

  dynamic "statement" {
    for_each = var.s3_workflow.enabled ? [1] : []

    content {
      resources = ["${local.bucket_arn}/*", ]

      actions = [
        "s3:GetObject",
        "s3:PutObject",
      ]
    }
  }

  dynamic "statement" {
    for_each = local.ecr_repository_prefixes != null && !var.s3_workflow.enabled ? local.ecr_repository_prefixes : [""]

    content {
      actions = [
        "ecr:CompleteLayerUpload",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart"
      ]
      resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${statement.value}*"]
    }
  }

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:ListImages",
      "ecr:ListTagsForResource"
    ]
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/*"]
  }

  dynamic "statement" {
    for_each = var.lambda_function_settings.container_uri != null ? [1] : []

    content {
      resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${replace(var.lambda_function_settings.container_uri, "/^[^/]+\\/|:.*$/", "")}*"]

      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:DescribeImages",
        "ecr:DescribeRepositories",
        "ecr:GetDownloadUrlForLayer",
        "ecr:GetLifecyclePolicy",
        "ecr:GetRepositoryPolicy",
        "ecr:ListImages",
        "ecr:ListTagsForResource"
      ]
    }
  }

  statement {
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "codebuild_assume_role" {
  count = var.s3_workflow.enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["codebuild.amazonaws.com"]
      type        = "Service"
    }
  }
}

#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "codebuild" {
  count = var.s3_workflow.enabled ? 1 : 0

  statement {
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.s3_workflow.codebuild_project_name}*", ]

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
  }

  dynamic "statement" {
    for_each = var.s3_workflow.enabled ? [1] : []

    content {
      actions = [
        "s3:GetObject",
        "s3:PutObject"
      ]

      resources = [
        local.bucket_arn,
        "${local.bucket_arn}/*"
      ]
    }
  }

  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = local.ecr_repository_prefixes != null ? local.ecr_repository_prefixes : [""]

    content {
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeRepositories",
        "ecr:GetDownloadUrlForLayer",
        "ecr:InitiateLayerUpload",
        "ecr:ListImages",
        "ecr:ListTagsForResource",
        "ecr:PutImage",
        "ecr:UploadLayerPart"
      ]
      resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${statement.value}*"]
    }
  }

  dynamic "statement" {
    for_each = length(aws_secretsmanager_secret_version.docker_hub_credentials[*].arn) > 0 ? [1] : []

    content {
      actions = [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetResourcePolicy",
        "secretsmanager:GetSecretValue",
        "secretsmanager:ListSecretVersionIds"
      ]
      resources = ["arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${local.docker_hub_cred_name}*"]
    }
  }
}

data "aws_iam_policy_document" "codepipeline_assume_role" {
  count = var.s3_workflow.enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["codepipeline.amazonaws.com"]
      type        = "Service"
    }
  }
}

#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "codepipeline" {
  count = var.s3_workflow.enabled ? 1 : 0

  statement {

    actions = [
      "s3:GetBucketVersioning",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject"
    ]

    resources = [
      local.bucket_arn,
      "${local.bucket_arn}/*"
    ]
  }

  statement {
    resources = [aws_codebuild_project.ecr_pull_push[0].arn]

    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild"
    ]
  }
}

resource "aws_iam_role" "lambda_assume_role" {
  name               = "ecr-sync-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy" "lamda_role" {
  role   = aws_iam_role.lambda_assume_role.name
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_iam_role" "codebuild_assume_role" {
  count = var.s3_workflow.enabled ? 1 : 0

  name               = "ecr-sync-codebuild"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role[0].json
}

resource "aws_iam_role_policy" "codebuild_role" {
  count = var.s3_workflow.enabled ? 1 : 0

  role   = aws_iam_role.codebuild_assume_role[0].name
  policy = data.aws_iam_policy_document.codebuild[0].json
}

resource "aws_iam_role" "codepipeline_assume_role" {
  count = var.s3_workflow.enabled ? 1 : 0

  name               = "ecr-sync-codepipeline"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume_role[0].json
}

resource "aws_iam_role_policy" "codepipeline_role" {
  count = var.s3_workflow.enabled ? 1 : 0

  role   = aws_iam_role.codepipeline_assume_role[0].name
  policy = data.aws_iam_policy_document.codepipeline[0].json
}
