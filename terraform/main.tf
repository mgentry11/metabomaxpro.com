# Main Terraform Configuration for MetaboMax Pro HIPAA Infrastructure

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure this after creating the S3 bucket for state
  # backend "s3" {
  #   bucket         = "metabomax-terraform-state"
  #   key            = "hipaa-infrastructure/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.metabomax_vpc.id
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.metabomax_primary.endpoint
  sensitive   = true
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = aws_lb.metabomax.dns_name
}

output "s3_phi_bucket" {
  description = "S3 bucket for PHI storage"
  value       = aws_s3_bucket.metabomax_phi.id
}

output "cloudtrail_name" {
  description = "CloudTrail name"
  value       = aws_cloudtrail.metabomax_audit.name
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.metabomax.name
}

output "ecr_repository_url" {
  description = "ECR repository URL for Docker images"
  value       = aws_ecr_repository.app.repository_url
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN (add DNS validation records)"
  value       = aws_acm_certificate.main.arn
}

output "acm_certificate_validation" {
  description = "ACM certificate DNS validation records"
  value       = aws_acm_certificate.main.domain_validation_options
}

output "sns_alerts_topic_arn" {
  description = "SNS topic ARN for security alerts"
  value       = aws_sns_topic.alerts.arn
}

output "secrets_manager_arn" {
  description = "Secrets Manager secret ARN"
  value       = aws_secretsmanager_secret.app_secrets.arn
}

output "nat_gateway_ips" {
  description = "NAT Gateway public IPs (whitelist these for external services)"
  value       = aws_eip.nat[*].public_ip
}
