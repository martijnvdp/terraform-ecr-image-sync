variable "codebuild_project_name" {
  type        = string
  description = "Name of the codebuild project."
  default     = "ecr-image-sync"
}

variable "codepipeline_name" {
  type        = string
  description = "Name of the codepipeline."
  default     = "ecr-image-sync"
}

variable "create_bucket" {
  type        = bool
  description = "Whether or not or not to create the s3 bucket."
  default     = true
}

variable "docker_images" {
  type = list(object({
    image_name   = string
    repo_prefix  = string
    include_tags = list(string)
    exclude_tags = list(string)
  }))
  description = "List of docker images to sync from Docker Hub to ECR."
}

variable "lambda_function_name" {
  type        = string
  description = "Name of the lambda function."
  default     = "ecr-image-sync"
}

variable "schedule" {
  type = object({
    name        = string
    expression  = string
    description = string
  })
  description = "Cloudwatch schedule event for the image synchronization in cron notation (UTC)."
  default = {
    name        = "ecr-schedule-public-images-sync"
    expression  = "cron(0 6 * * ? *)"
    description = "Synchronization cloudwatch schedule of the public docker images."
  }
}

variable "s3_bucket" {
  type        = string
  description = "S3 bucket name for the storage of the csv file with the list of images to be synced."
  default     = "ecr-image-sync"
}

variable "tags" {
  type        = map(string)
  description = "A mapping of tags assigned to the resources."
}
