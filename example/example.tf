module "ecr-image-sync" {
  source                   = "../"
  dockerhub_credentials_sm = "aws_ssm_secret_name" //optional name of the aws secret item with dockerhub credentials , keys username & password
  debug                    = true                  //optional turn on debug logging
  default_repo_prefix      = "/default/prefix"     //optional default repo prefix for all images , is overridden by the individual setting

  dockerhub_credentials_ssm = { // optional AWS SSM parameter store item names for dockerhub username and password
    username_item = "/dockerhub/username"
    password_item = "/dockerhub/password"
  }

  docker_images = {
    "hashicorp/tfc-agent" = {   // full image name on docker
      repo_prefix  = "int/ecr"  // ecr repo prefix
      include_tags = ["latest"] // list of tags to be included
      exclude_tags = []         // list of tags to be excluded
    }
    "datadog/agent" = { repo_prefix = "int/ecr", exclude_tags = ["latest", "6.27.0-rc.1"] }
  }
}
