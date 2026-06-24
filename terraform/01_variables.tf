variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "resilient-order-platform"
}

variable "db_name" {
  description = "Aurora database name"
  type        = string
  default     = "orders"
}

variable "db_master_username" {
  description = "Aurora master username"
  type        = string
  default     = "orders_admin"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.42.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets across"
  type        = number
  default     = 2
}
