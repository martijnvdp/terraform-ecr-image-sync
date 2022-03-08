data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda" {
  statement {
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.lambda_function_name}*", ]

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
  }

  statement {
    resources = ["arn:aws:xray:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}*", ]

    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
      "xray:GetSamplingStatisticSummaries"
    ]
  }
  statement {
    resources = ["${local.bucket_arn}/*", ]

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
  }

  statement {
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}*", ]

    actions = [
      "ecr:DescribeRepositories",
      "ecr:ListTagsForResource",
      "ecr:ListImages"
    ]
  }

  statement {
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository${var.lambda_function_repo}*"]

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetLifecyclePolicy",
      "ecr:GetRepositoryPolicy",
      "ecr:GetDownloadUrlForLayer",
      "ecr:ListTagsForResource",
      "ecr:ListImages"
    ]
  }
}

data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.codebuild_project_name}*", ]

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
  }

  statement {

    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]

    resources = [
      local.bucket_arn,
      "${local.bucket_arn}/*",
    ]
  }

  statement {
    resources = ["*"]
    actions   = ["ecr:GetAuthorizationToken"]
  }

  statement {
    resources = ["arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}*", ]

    actions = [
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]
  }

  dynamic "statement" {
    for_each = length(aws_secretsmanager_secret_version.docker_hub_credentials[*].arn) > 0 ? aws_secretsmanager_secret_version.docker_hub_credentials[*].arn : []
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
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "codepipeline" {
  statement {

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObject"
    ]

    resources = [
      local.bucket_arn,
      "${local.bucket_arn}/*"
    ]
  }

  statement {
    resources = [aws_codebuild_project.ecr_pull_push.arn]

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
  name               = "ecr-sync-codebuild"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
}

resource "aws_iam_role_policy" "codebuild_role" {
  role   = aws_iam_role.codebuild_assume_role.name
  policy = data.aws_iam_policy_document.codebuild.json
}

resource "aws_iam_role" "codepipeline_assume_role" {
  name               = "ecr-sync-codepipeline"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume_role.json
}

resource "aws_iam_role_policy" "codepipeline_role" {
  role   = aws_iam_role.codepipeline_assume_role.name
  policy = data.aws_iam_policy_document.codepipeline.json
}
