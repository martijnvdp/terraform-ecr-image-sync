// all 4 fields are required for the docker images https://github.com/hashicorp/terraform/issues/19898
module "ecr-image-sync" {
  source = "../"
  docker_images = [
    {
      image_name   = "hashicorp/tfc-agent" // full image name on docker
      repo_prefix  = "int/ecr"             // ecr repo prefix
      include_tags = ["latest"]            // list of tags to be included
      exclude_tags = []                    // list of tags to be excluded
    },
    {
      image_name   = "datadog/agent"
      repo_prefix  = "int/ecr"
      include_tags = []
      exclude_tags = ["latest", "6.27.0-rc.1"]
    }
  ]
}
