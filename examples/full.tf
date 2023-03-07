locals {
  ecr_lambda_repositories = ["martijnvdp/lambda-ecr-image-sync"]

  # The equality operators are equal (-eq), greater than (-gt), greater than or equal (-ge), less than (-lt), and less than or equal (-le)
  ecr_repositories = {
    "dev/isovalent/cilium"                     = { source = "quay.io/isovalent/cilium", constraint = "-ge v1.10.3", include_rls = "cee", include_tags = "current" }
    "dev/openpolicyagent/gatekeeper"           = { source = "docker.io/openpolicyagent/gatekeeper", constraint = "-ge v3.9.0" }
    "dev/otel/opentelemetry-collector-contrib" = { source = "docker.io/otel/opentelemetry-collector-contrib", constraint = "-ge 0.66.0" }
    "dev/grafana/grafana"                      = { source = "docker.io/grafana/grafana", constraint = "-ge 9.3.1" }
    "dev/redis"                                = { source = "docker.io/redis", constraint = "-ge 7.0.4", include_rls = "alpine", release_only = "true" }
    "test/nginx"                               = { source = "docker.io/nginx", constraint = "-ge 1.21" }
  }
}

data "aws_kms_key" "cmk" {
  key_id = "alias/my-cmk"
}

provider "aws" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

module "ecr" {
  source = "github.com/schubergphilis/terraform-aws-mcaf-ecr?ref=v1.1.0"

  image_tag_mutability       = "MUTABLE"
  kms_key_arn                = data.aws_kms_key.cmk.arn
  principals_readonly_access = [data.aws_caller_identity.current.account_id]
  repository_names           = [for k, _ in local.ecr_repositories : k]
  repository_tags            = { for name, tags in local.ecr_repositories : name => merge({ ecr_sync_opt = "in" }, { for k, v in tags : "ecr_sync_${k}" => v }) if try(tags.source, "") != "" }
}

module "ecr_lambda" {
  count  = length(local.ecr_lambda_repositories) > 0 ? 1 : 0
  source = "github.com/schubergphilis/terraform-aws-mcaf-ecr?ref=v1.1.0"

  image_tag_mutability       = "MUTABLE"
  kms_key_arn                = data.aws_kms_key.cmk.arn
  principals_readonly_access = [data.aws_caller_identity.current.account_id]
  repository_names           = local.ecr_lambda_repositories
  tags                       = {}

  additional_ecr_policy_statements = {
    LambdaECRImageRetrievalPolicy = {
      effect = "Allow"
      principal = {
        type        = "Service"
        identifiers = ["lambda.amazonaws.com"]
      }
      actions = [
        "ecr:BatchGetImage",
        "ecr:DeleteRepositoryPolicy",
        "ecr:GetDownloadUrlForLayer",
        "ecr:GetRepositoryPolicy",
        "ecr:SetRepositoryPolicy"
      ]
    }
  }
}

// ECR Image Sync Lambda function
module "ecrImageSync" {
  source = "../"

  // docker_hub_credentials  = var.docker_hub_credentials // optional
  ecr_repository_prefixes = distinct([for repo, tags in local.ecr_repositories : regex("^(\\w+)/.*$", repo)[0] if try(tags.source, "") != ""])

  // source container image: docker pull ghcr.io/martijnvdp/lambda-ecr-image-sync:v1.0.3
  lambda_function_settings = {
    container_uri = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/martijnvdp/lambda-ecr-image-sync:v1.0.3"

    event_rules = {

      scheduled_event = {
        schedule_expression = "cron(0 7 * * ? *)"
      }
    }

    sync_settings = {
      check_digest = true
      max_results  = 5
    }
  }
}
