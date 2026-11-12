variable "aws_region" {
  description = "AWS Region; tutorial tested conceptually for us-east-1"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for managed demo resources"
  type        = string
  default     = "cloudops-autoremediate"
}

variable "enable_config_recorder" {
  description = "False if a customer-managed AWS Config recorder already exists in this Region"
  type        = bool
  default     = true
}
