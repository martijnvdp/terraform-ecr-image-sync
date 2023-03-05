![terraform tests](https://github.com/martijnvdp/terraform-ecr-image-sync/actions/workflows/terraform.yml/badge.svg)

Terraform module for AWS to create a lambda for syncing images <br>
between private aws/ecr and public ecrs like dockerhub/ghcr.io/quay.io
## Docker images lambda function

- `docker pull ghcr.io/martijnvdp/ecr-image-sync:latest`

see the source repo https://github.com/martijnvdp/lambda-ecr-image-sync

## configure repositories to sync using tags

Configure repository to sync using tags on repositories
see the full example and the source repo of the lambda 
https://github.com/martijnvdp/lambda-ecr-image-sync


```hcl
module "ecrImageSync" {
  source = "../"

  docker_hub_credentials  = var.docker_hub_credentials // optional
  ecr_repository_prefixes = distinct([for repo, tags in local.ecr_repositories : regex("^(\\w+)/.*$", repo)[0] if try(tags.source, "") != ""])

  // source container image: docker pull ghcr.io/martijnvdp/ecr-image-sync:latest
  lambda = {
    container_uri = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/images/ecr-image-sync:v1.0.2"

    event_rules = {

      scheduled_event = {
        schedule_expression = "cron(0 7 * * ? *)"
      }
    }

    settings = {
      check_digest    = true
      ecr_repo_prefix = ""
      max_results     = 5
      slack_errors_only = true // only errors to slack
      slack_channel_id  = "" // optional slack channel id
    }
  }
}

```
<!--- BEGIN_TF_DOCS --->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| aws | n/a |
| random | n/a |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| codebuild\_project\_name | Name of the codebuild project | `string` | `"ecr-image-sync"` | no |
| codepipeline\_name | Name of the codepipeline | `string` | `"ecr-image-sync"` | no |
| crane\_version | Crane version | `string` | `"v0.11.0"` | no |
| debug | Debug logging setting for the lambda | `bool` | `false` | no |
| docker\_hub\_credentials | Dockerhub credentials: {"username":"docker\_username","password":"docker\_password"} | `string` | `null` | no |
| docker\_hub\_credentials\_sm\_item\_name | AWS Secretsmanager item name for dockerhub credentials | `string` | `"docker-hub-ecr-image-sync"` | no |
| docker\_images | List of docker images to sync from Docker Hub to ECR | `any` | `null` | no |
| docker\_images\_defaults | Default values for the docker images variable | <pre>object({<br>    image_name     = string<br>    repo_prefix    = string<br>    include_regexp = string<br>    include_tags   = list(string)<br>    exclude_regexp = string<br>    exclude_tags   = list(string)<br>    max_results    = number<br>  })</pre> | <pre>{<br>  "exclude_regexp": null,<br>  "exclude_tags": [],<br>  "image_name": null,<br>  "include_regexp": null,<br>  "include_tags": [],<br>  "max_results": null,<br>  "repo_prefix": null<br>}</pre> | no |
| lambda\_function\_container\_uri | Ecr url of the docker container for the lambda function | `string` | `null` | no |
| lambda\_function\_name | Name of the lambda function | `string` | `"ecr-image-sync"` | no |
| lambda\_function\_repo | ECR repo of the lambda function container image | `string` | `"/base/infra/ccvhosting/ecr-image-sync"` | no |
| lambda\_function\_settings | Settings for the ecr-image-sync function | <pre>object({<br>    check_digest    = bool<br>    ecr_repo_prefix = string<br>    max_results     = number<br>  })</pre> | `null` | no |
| lambda\_function\_zip\_file\_folder | Folder containing the zip file for the lambda function | `string` | `"dist"` | no |
| s3\_workflow | S3 bucket workflow options | <pre>object({<br>    bucket        = optional(string, "ecr-image-sync")<br>    create_bucket = optional(bool, true)<br>    enabled       = optional(bool, true)<br>  })</pre> | `{}` | no |
| schedule\_expression | Cloudwatch schedule event for the image synchronization in cron notation (UTC) | `string` | `"cron(0 6 * * ? *)"` | no |
| tags | A mapping of tags assigned to the resources | `map(string)` | `null` | no |

## Outputs

No output.

<!--- END_TF_DOCS --->
