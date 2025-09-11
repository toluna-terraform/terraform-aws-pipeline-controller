variable "pipeline_type" {
  type = string
}

variable "trigger_branch" {
  type = string
}

variable "env_name" {
  type = string
}

variable "app_name" {
  type = string
}

variable "app_type" {
  default = "ecs"
  type = string
}

variable "domain" {
  type = string
}

variable "env_type" {
  type = string
}

variable "path_pattern" {
  type = string
}

variable "source_repository" {
    type = string
}

variable "is_managed_env" {
    type = string
}

variable "bucket_id" {
  type = string
}

variable "aws_profile" {
  type = string
}

variable "ttl" {
  type = number
  default = 300
}

variable "tribe_state_bucket" {
  type = string
}