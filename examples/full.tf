locals {

  ecr_lambda_repositories = ["images/lambda-ecr-image-sync"]
  deploy_ecr_sync         = true

  # The equality operators are equal (-eq), greater than (-gt), greater than or equal (-ge), less than (-lt), and less than or equal (-le)
  image_sync_images = {
    "dev" = {
      "quay.io/isovalent/cilium"                       = { ecr_sync_constraint = "-ge v1.10.3", ecr_sync_include_rls = "cee", ecr_sync_include_tags = "current" }
      "docker.io/openpolicyagent/gatekeeper"           = { ecr_sync_constraint = "-ge v3.9.0" }
      "docker.io/otel/opentelemetry-collector-contrib" = { ecr_sync_constraint = "-ge 0.66.0" }
      "docker.io/grafana/grafana"                      = { ecr_sync_constraint = "-ge 9.3.1" }
      "docker.io/redis"                                = { ecr_sync_constraint = "-ge 7.0.4", ecr_sync_include_rls = "alpine", ecr_sync_release_only = "true" }
    }
    "test" = {
      "docker.io/nginx" = { ecr_sync_constraint = "-ge 1.21" }
    }
  }

  image_sync_ecr_map = flatten([
    for repo, v in local.image_sync_images : [
      for name, options in v : {
        repository_name = length(split("/", name)) == 3 ? "${repo}/${split("/", name)[1]}/${split("/", name)[2]}" : "${repo}/${split("/", name)[1]}"
        tags = merge(options, {
          ecr_sync_opt    = "in"
          ecr_sync_source = name
        })
      }
    ]
  ])
}

data "aws_kms_key" "cmk" {
  key_id = "alias/my-cmk"
}

provider "aws" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

module "ecr" {
  count  = 1
  source = "github.com/martijnvdp/terraform-aws-mcaf-ecr?ref=repository-tags"

  image_tag_mutability       = "MUTABLE"
  principals_readonly_access = [data.aws_caller_identity.current.account_id]
  repository_names           = [for k, v in local.image_sync_ecr_map : v.repository_name]
  kms_key_arn                = data.aws_kms_key.cmk.arn

  repository_tags = { for _, v in local.image_sync_ecr_map : v.repository_name => try(v.tags, {})
    if try(v.tags.ecr_sync_opt, "") == "in"
  }
}

// ECR Image Sync Lambda function
module "ecrImageSync" {
  source = "../"

  // docker_hub_credentials        = var.docker_hub_credentials
  // source container image: docker pull ghcr.io/martijnvdp/ecr-image-sync:latest
  lambda_function_container_uri = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/images/lambda-ecr-image-sync:v1.0.1"
  schedule_expression           = "cron(0 7 * * ? *)"

  lambda_function_settings = {
    check_digest    = true
    ecr_repo_prefix = ""
    max_results     = 10
  }

  providers = {
    aws = aws
  }

  s3_workflow = {
    enabled = false
  }
}

// ECR for the Lambda function container image
module "ecrLambda" {
  count  = length(local.ecr_lambda_repositories) > 0 && local.deploy_ecr_sync ? 1 : 0
  source = "github.com/schubergphilis/terraform-aws-mcaf-ecr?ref=v1.1.0"

  image_tag_mutability       = "MUTABLE"
  kms_key_arn                = data.aws_kms_key.cmk.arn
  principals_readonly_access = [data.aws_caller_identity.current.account_id]
  repository_names           = local.ecr_lambda_repositories

  additional_ecr_policy_statements = {
    LambdaECRImageRetrievalPolicy = {
      effect = "allow"
      principal = {
        type        = "service"
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
