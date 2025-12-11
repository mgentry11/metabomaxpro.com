# Terraform Variables for MetaboMax Pro HIPAA Infrastructure

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_username" {
  description = "Database administrator username"
  type        = string
  default     = "metabomax_admin"
  sensitive   = true
}

variable "db_password" {
  description = "Database administrator password"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "metabomaxpro"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 100
}

variable "app_image" {
  description = "Docker image for Flask application"
  type        = string
  default     = "metabomax-app:latest"
}

variable "app_cpu" {
  description = "CPU units for ECS task"
  type        = string
  default     = "512"
}

variable "app_memory" {
  description = "Memory for ECS task in MB"
  type        = string
  default     = "1024"
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "metabomaxpro.com"
}

variable "enable_multi_az" {
  description = "Enable Multi-AZ for RDS"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for RDS"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 365
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "MetaboMax Pro"
    Compliance  = "HIPAA"
    ManagedBy   = "Terraform"
    Environment = "Production"
  }
}
