# Usage
<!--- BEGIN_TF_DOCS --->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| aws | n/a |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| tags | A mapping of tags assigned to the resources. | `map(string)` | n/a | yes |
| codebuild\_project\_name | Name of the codebuild project. | `string` | `"ecr-image-sync"` | no |
| codepipeline\_name | Name of the codepipeline. | `string` | `"ecr-image-sync"` | no |
| create\_bucket | Whether or not or not to create the s3 bucket. | `bool` | `true` | no |
| docker\_images | List of docker images to sync from Docker Hub to ECR. | `any` | `{}` | no |
| docker\_images\_defaults | Default values for the docker images variable. | <pre>object({<br>    image_name   = string<br>    repo_prefix  = string<br>    include_tags = list(string)<br>    exclude_tags = list(string)<br>  })</pre> | <pre>{<br>  "exclude_tags": [],<br>  "image_name": null,<br>  "include_tags": [],<br>  "repo_prefix": null<br>}</pre> | no |
| lambda\_function\_name | Name of the lambda function. | `string` | `"ecr-image-sync"` | no |
| s3\_bucket | S3 bucket name for the storage of the csv file with the list of images to be synced. | `string` | `"ecr-image-sync"` | no |
| schedule\_expression | Cloudwatch schedule event for the image synchronization in cron notation (UTC). | `string` | `"cron(0 6 * * ? *)"` | no |

## Outputs

No output.

<!--- END_TF_DOCS --->
