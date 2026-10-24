variable "aws_region" {
  description = "AWS region where resources will be provisioned."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "The size/type of the EC2 instance."
  type        = string
  default     = "t3.micro"
}

variable "project_name" {
  description = "The name of the project. Used to prefix and tag resources."
  type        = string
  default     = "startuptech"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "The environment variable must be one of: dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "The IP range (CIDR block) for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr_block" {
  description = "The CIDR block the public subnet's resources can reside in the VPC."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidr_block" {
  description = "The CIDR block the private subnet's resources can reside in the VPC."
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "my_ip" {
  description = "My personal IP address"
  type        = string
}
