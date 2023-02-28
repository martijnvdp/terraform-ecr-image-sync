![terraform tests](https://github.com/martijnvdp/terraform-ecr-image-sync/actions/workflows/terraform.yml/badge.svg)

Terraform module for AWS to create a lambda for syncing images <br>
between private aws/ecr and public ecrs like dockerhub/ghcr.io/quay.io
## Docker images lambda function

- `docker pull ghcr.io/martijnvdp/ecr-image-sync:latest`

see the source repo https://github.com/martijnvdp/lambda-ecr-image-sync

## Usage using repository tags

add repository tags to configure sync options

see full example

## Usage example json payload
docker_image var is optional you can also configure repository to sync using tags on repositories
see the full example and the source repo of the lambda 
https://github.com/martijnvdp/lambda-ecr-image-sync


```hcl
module "ecr-image-sync" {
  source                        = "../"
  lambda_function_container_uri = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/images/ccvhosting/ecr-image-sync:v0.1.7"
  slack_oauth_token             = var.slackOAuthToken
  tags                          = module.tags.tags

  docker_images = {
    "images" = { //prefix , example targetecr/infra/bitnami/external-dns
      "docker.io/bitnami/external-dns"      = { constraint = ">= 0.7.3", include_rels = ["debian"] }
      "docker.io/ccvhosting/ecr-image-sync" = { constraint = "~> v0.1.0", include_rels = ["rc"], type = "lambda" }
      "ghcr.io/some/image"                  = { constraint = ">= v2.30.0" }
      "quay.io/someother/image"             = { constraint = ">= v2.2.5" }
    }
    "other/images/prefix" = {
      "docker.io/nginx" = { constraint = ">= 1.21" }
    }
  }

  lambda_function_settings = {
    check_digest      = true // check image digest with existing images 
    ecr_repo_prefix   = "" // optional global ecr prefix
    max_results       = 2  // max image results 
    slack_errors_only = true // only errors to slack
    slack_channel_id  = "" // optional slack channel id
  }
}

```
<!--- BEGIN_TF_DOCS --->

<!--- END_TF_DOCS --->
