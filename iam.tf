data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda" {
  statement {
    effect    = "Allow"
    resources = ["arn:aws:logs:*:*:*", ]

    actions = [
      "logs:PutLogEvents",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
    ]
  }

  statement {
    effect    = "Allow"
    resources = ["${local.bucket_arn}/*", ]

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
  }

  statement {
    effect    = "Allow"
    resources = ["*", ]

    actions = [
      "ecr:DescribeRepositories",
      "ecr:ListTagsForResource",
      "ecr:ListImages"
    ]
  }
}

data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    effect    = "Allow"
    resources = ["*", ]

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
  }

  statement {
    effect = "Allow"

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
    actions   = ["ecr:*"]
    effect    = "Allow"
    resources = ["*", ]
  }

  dynamic "statement" {
    for_each = var.dockerhub_credentials_sm != null ? [var.dockerhub_credentials_sm] : []
    content {
      actions = [
        "secretsmanager:GetResourcePolicy",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecretVersionIds"
      ]
      effect    = "Allow"
      resources = ["arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${statement.value}*"]
    }
  }

  dynamic "statement" {
    for_each = var.dockerhub_credentials_ssm.password_item != null ? [var.dockerhub_credentials_ssm] : []
    content {
      actions = ["ssm:GetParameters"]
      effect  = "Allow"
      resources = [
        "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${statement.value.password_item}",
        "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${statement.value.username_item}"
      ]
    }
  }
}

data "aws_iam_policy_document" "codepipeline_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "codepipeline" {
  statement {
    effect = "Allow"

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
    effect    = "Allow"
    resources = ["*", ]

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

