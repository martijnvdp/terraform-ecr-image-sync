![terraform tests](https://github.com/martijnvdp/terraform-ecr-image-sync/actions/workflows/terraform.yml/badge.svg)

Terraform module for AWS to create a lambda for syncing images <br>
between private aws/ecr and public ecrs like dockerhub/ghcr.io/quay.io
## Docker images lambda function

- `docker pull ghcr.io/martijnvdp/lambda-ecr-image-sync:v1.0.3`

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
| docker\_hub\_credentials | Dockerhub credentials: {"username":"docker\_username","password":"docker\_password"} | `string` | `null` | no |
| docker\_hub\_credentials\_sm\_item\_name | AWS Secretsmanager item name for dockerhub credentials | `string` | `"docker-hub-ecr-image-sync"` | no |
| ecr\_repository\_prefixes | List of ECR repository prefixes to give the lambda function access for pushing images to | `list(string)` | `null` | no |
| lambda\_function\_settings | Lambda function options | <pre>object({<br>    name            = optional(string, "ecr-image-sync")<br>    container_uri   = optional(string, null)<br>    timeout         = optional(number, 900)<br>    zip_file_folder = optional(string, "dist")<br>    event_rules = optional(object({<br>      payload_updated = optional(object({<br>        description = optional(string, "Capture all updated input JSON events: ECRImageSyncScheduledEvent")<br>        is_enabled  = optional(bool, false)<br>      }), {}),<br>      repository_tags = optional(object({<br>        description = optional(string, "Capture each ECR repository tag changed event")<br>        is_enabled  = optional(bool, true)<br>      }), {})<br>      scheduled_event = optional(object({<br>        description         = optional(string, "CloudWatch schedule for synchronization of the public Docker images.")<br>        is_enabled          = optional(bool, true)<br>        schedule_expression = optional(string, "cron(0 6 * * ? *)")<br>      }), {})<br>    }), {})<br>    sync_settings = optional(object({<br>      check_digest = optional(bool, true)<br>      max_results  = optional(number, 100)<br>    }), {})<br>  })</pre> | `{}` | no |
| s3\_workflow | S3 bucket workflow options | <pre>object({<br>    bucket                 = optional(string, "ecr-image-sync")<br>    codebuild_project_name = optional(string, "ecr-image-sync")<br>    codepipeline_name      = optional(string, "ecr-image-sync")<br>    crane_version          = optional(string, "v0.11.0")<br>    create_bucket          = optional(bool, true)<br>    debug                  = optional(bool, false)<br>    enabled                = optional(bool, false)<br>  })</pre> | `{}` | no |
| tags | A mapping of tags assigned to the resources | `map(string)` | `null` | no |

## Outputs

No output.

<!--- END_TF_DOCS --->
