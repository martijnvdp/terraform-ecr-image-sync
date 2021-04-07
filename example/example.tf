module "ecr-image-sync" {
  source = "../"
  docker_images = {
    "hashicorp/tfc-agent" = {   // full image name on docker
      repo_prefix  = "int/ecr"  // ecr repo prefix
      include_tags = ["latest"] // list of tags to be included
      exclude_tags = []         // list of tags to be excluded
    }
    "datadog/agent" = {
      repo_prefix  = "int/ecr"
      exclude_tags = ["latest", "6.27.0-rc.1"]
    }
  }
}
