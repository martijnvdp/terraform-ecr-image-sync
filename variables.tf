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

variable "ecr_repository_prefixes" {
  type        = list(string)
  description = "List of ECR repository prefixes to give the lambda function access for pushing images to"
  default     = null
}

variable "lambda" {
  type = object({
    name            = optional(string, "ecr-image-sync")
    container_uri   = optional(string, null)
    zip_file_folder = optional(string, "dist")
    event_rules = optional(object({
      payload_updated = optional(object({
        description = optional(string, "Capture all updated input JSON events: ECRImageSyncScheduledEvent")
        is_enabled  = optional(bool, true)
      }), {}),
      repository_created = optional(object({
        description = optional(string, "CloudWatch event rule for ECR repository created")
        is_enabled  = optional(bool, true)
      }), {}),
      repository_tags = optional(object({
        description = optional(string, "Capture each ECR repository tag changed event")
        is_enabled  = optional(bool, true)
      }), {})
      scheduled_event = optional(object({
        description         = optional(string, "CloudWatch schedule for synchronization of the public Docker images.")
        is_enabled          = optional(bool, true)
        schedule_expression = optional(string, "cron(0 6 * * ? *)")
      }), {})
    }), {})
    settings = optional(object({
      check_digest    = optional(bool, true)
      ecr_repo_prefix = optional(string, "dockerhub")
      max_results     = optional(number, 100)
    }), {})
  })
  description = "Lambda function options"
  default     = {}
}

variable "s3_workflow" {
  type = object({
    bucket                 = optional(string, "ecr-image-sync")
    codebuild_project_name = optional(string, "ecr-image-sync")
    codepipeline_name      = optional(string, "ecr-image-sync")
    crane_version          = optional(string, "v0.11.0")
    create_bucket          = optional(bool, true)
    debug                  = optional(bool, false)
    enabled                = optional(bool, true)
  })
  description = "S3 bucket workflow options"
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "A mapping of tags assigned to the resources"
  default     = null
}
