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

variable "debug" {
  type        = bool
  description = "Debug logging."
  default     = false
}

variable "default_repo_prefix" {
  type        = string
  description = "Default repo prefix value for all images."
  default     = null
}

variable "dockerhub_credentials_sm" {
  type        = string
  description = "AWS secretsmanager item name containing dockerhub credentials (keys:username and password)."
  default     = null
}

variable "dockerhub_credentials_ssm" {
  type = object({
    username_item = string
    password_item = string
  })
  description = "AWS SSM parameter store items containing dockerhub credentials."
  default = {
    username_item = null
    password_item = null
  }
}

variable "docker_images_defaults" {
  type = object({
    image_name   = string
    repo_prefix  = string
    include_tags = list(string)
    exclude_tags = list(string)
  })
  description = "Default values for the docker images variable."
  default = {
    image_name   = null
    repo_prefix  = null
    include_tags = []
    exclude_tags = []
  }
}

variable "docker_images" {
  type        = any
  description = "List of docker images to sync from Docker Hub to ECR."
}

variable "lambda_function_name" {
  type        = string
  description = "Name of the lambda function."
  default     = "ecr-image-sync"
}

variable "schedule_expression" {
  type        = string
  description = "Cloudwatch schedule event for the image synchronization in cron notation (UTC)."
  default     = "cron(0 6 * * ? *)"
}

variable "s3_bucket" {
  type        = string
  description = "S3 bucket name for the storage of the csv file with the list of images to be synced."
  default     = "ecr-image-sync"
}

variable "tags" {
  type        = map(string)
  description = "A mapping of tags assigned to the resources."
  default     = null
}
