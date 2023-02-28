variable "codebuild_project_name" {
  type        = string
  description = "Name of the codebuild project"
  default     = "ecr-image-sync"
}

variable "codepipeline_name" {
  type        = string
  description = "Name of the codepipeline"
  default     = "ecr-image-sync"
}

variable "crane_version" {
  type        = string
  description = "Crane version"
  default     = "v0.11.0"
}

variable "debug" {
  type        = bool
  description = "Debug logging setting for the lambda"
  default     = false
}

variable "docker_hub_credentials" {
  type        = string
  description = "Dockerhub credentials: {\"username\":\"docker_username\",\"password\":\"docker_password\"}"
  sensitive   = true
  default     = null
}

variable "docker_hub_credentials_sm_item_name" {
  type        = string
  description = "AWS Secretsmanager item name for dockerhub credentials"
  default     = "docker-hub-ecr-image-sync"
}

variable "docker_images" {
  type        = any
  description = "List of docker images to sync from Docker Hub to ECR"
  default     = null
}

variable "docker_images_defaults" {
  type = object({
    image_name     = string
    repo_prefix    = string
    include_regexp = string
    include_tags   = list(string)
    exclude_regexp = string
    exclude_tags   = list(string)
    max_results    = number
  })
  description = "Default values for the docker images variable"
  default = {
    image_name     = null
    repo_prefix    = null
    include_regexp = null
    include_tags   = []
    exclude_regexp = null
    exclude_tags   = []
    max_results    = null
  }
}

variable "lambda_function_container_uri" {
  type        = string
  description = "Ecr url of the docker container for the lambda function"
  default     = null
}

variable "lambda_function_name" {
  type        = string
  description = "Name of the lambda function"
  default     = "ecr-image-sync"
}

variable "lambda_function_repo" {
  type        = string
  description = "ECR repo of the lambda function container image"
  default     = "/base/infra/ccvhosting/ecr-image-sync"
}

variable "lambda_function_settings" {
  type = object({
    check_digest    = bool
    ecr_repo_prefix = string
    max_results     = number
  })
  description = "Settings for the ecr-image-sync function"
  default     = null
}

variable "lambda_function_zip_file_folder" {
  type        = string
  description = "Folder containing the zip file for the lambda function"
  default     = "dist"
}

variable "s3_workflow" {
  type = object({
    bucket        = optional(string, "ecr-image-sync")
    create_bucket = optional(bool, true)
    enabled       = optional(bool, true)
  })
  description = "S3 bucket workflow options"
  default     = {}
}

variable "schedule_expression" {
  type        = string
  description = "Cloudwatch schedule event for the image synchronization in cron notation (UTC)"
  default     = "cron(0 6 * * ? *)"
}

variable "tags" {
  type        = map(string)
  description = "A mapping of tags assigned to the resources"
  default     = null
}
