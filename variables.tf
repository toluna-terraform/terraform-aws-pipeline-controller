variable "apps" {
}

variable "app_name" {
  type = string
}

variable "path_pattern" {
  type = string
}

variable "source_repository" {
    type = string
}

variable "env_type" {
    type = string
}

variable "domain" {
    type = string
}

variable "app_type" {
  default = "ecs"
  type = string
}

variable "aws_profile" {
  type = string
}

variable "ttl" {
  type = number
  default = 300
}

variable "tribe" {
  type = string
}