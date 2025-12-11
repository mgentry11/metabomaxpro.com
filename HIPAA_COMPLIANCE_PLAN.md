# MetaboMax Pro HIPAA Compliance Implementation Plan

## Executive Summary

This document outlines the comprehensive HIPAA compliance implementation plan for the MetaboMax Pro ecosystem. The platform currently processes Protected Health Information (PHI) including metabolic test results, biological age data, and personalized health recommendations, requiring full HIPAA compliance.

**Current Architecture Assessment:**
- **Backend**: Flask app on Render.com (NOT HIPAA compliant)
- **Database**: Supabase PostgreSQL (NOT HIPAA compliant by default)
- **AI Processing**: OpenAI API (requires BAA for HIPAA)
- **File Storage**: Render.com ephemeral storage (NOT compliant)
- **Frontend**: Static website served from /Sites/metabomaxpro.com

**Critical PHI Data Types:**
- VO2 max values
- Resting Metabolic Rate (RMR)
- Respiratory Exchange Ratio (RER)
- Heart rate data
- Biological age calculations
- Personal identifiers (name, email, date of birth)

---

## Part 1: AWS Infrastructure HIPAA Compliance

### 1.1 AWS Business Associate Agreement (BAA)

**Action Items:**
1. Sign up for AWS account (if not already done)
2. Navigate to AWS Artifact portal
3. Download and accept the AWS BAA
4. Enable HIPAA-eligible services in your AWS account

**Required Services for BAA:**
- Amazon EC2 (compute)
- Amazon RDS (database)
- Amazon S3 (file storage)
- Amazon VPC (networking)
- AWS KMS (encryption key management)
- Amazon CloudWatch (logging)
- AWS CloudTrail (audit logging)
- Amazon ECS/EKS or Elastic Beanstalk (container/app hosting)

**Documentation:**
- Store signed BAA in secure location
- Maintain compliance documentation
- Review BAA annually

### 1.2 Virtual Private Cloud (VPC) Configuration

**VPC Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                      AWS VPC (10.0.0.0/16)                  │
│                                                              │
│  ┌─────────────────────┐    ┌──────────────────────┐       │
│  │  Public Subnet      │    │   Public Subnet      │       │
│  │  (10.0.1.0/24)      │    │   (10.0.2.0/24)      │       │
│  │  - NAT Gateway      │    │   - ALB              │       │
│  │  - Bastion Host     │    │                      │       │
│  └─────────────────────┘    └──────────────────────┘       │
│                                                              │
│  ┌─────────────────────┐    ┌──────────────────────┐       │
│  │  Private Subnet     │    │   Private Subnet     │       │
│  │  (10.0.10.0/24)     │    │   (10.0.11.0/24)     │       │
│  │  - EC2 Instances    │    │   - EC2 Instances    │       │
│  │  - ECS Tasks        │    │   - ECS Tasks        │       │
│  └─────────────────────┘    └──────────────────────┘       │
│                                                              │
│  ┌─────────────────────┐    ┌──────────────────────┐       │
│  │  Database Subnet    │    │   Database Subnet    │       │
│  │  (10.0.20.0/24)     │    │   (10.0.21.0/24)     │       │
│  │  - RDS Primary      │    │   - RDS Replica      │       │
│  └─────────────────────┘    └──────────────────────┘       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Terraform Configuration Example:**
```hcl
# vpc.tf
resource "aws_vpc" "metabomax_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "metabomax-hipaa-vpc"
    Environment = "production"
    Compliance  = "HIPAA"
  }
}

resource "aws_subnet" "private_app_subnet_a" {
  vpc_id            = aws_vpc.metabomax_vpc.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "metabomax-private-app-a"
    Type = "Private"
  }
}

resource "aws_subnet" "private_db_subnet_a" {
  vpc_id            = aws_vpc.metabomax_vpc.id
  cidr_block        = "10.0.20.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "metabomax-private-db-a"
    Type = "Database"
  }
}
```

### 1.3 Security Groups Configuration

**Application Security Group:**
```hcl
# security_groups.tf
resource "aws_security_group" "app_sg" {
  name        = "metabomax-app-sg"
  description = "Security group for Flask application servers"
  vpc_id      = aws_vpc.metabomax_vpc.id

  # Inbound from ALB only
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Outbound to RDS
  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.rds_sg.id]
  }

  # Outbound for HTTPS (API calls to OpenAI/Stripe)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name       = "metabomax-app-sg"
    Compliance = "HIPAA"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "metabomax-rds-sg"
  description = "Security group for RDS database"
  vpc_id      = aws_vpc.metabomax_vpc.id

  # Inbound from app servers only
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  tags = {
    Name       = "metabomax-rds-sg"
    Compliance = "HIPAA"
  }
}
```

### 1.4 AWS KMS Encryption Key Management

**KMS Configuration:**
```hcl
# kms.tf
resource "aws_kms_key" "metabomax_hipaa" {
  description             = "MetaboMax Pro HIPAA encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name       = "metabomax-hipaa-key"
    Compliance = "HIPAA"
  }
}

resource "aws_kms_alias" "metabomax_hipaa" {
  name          = "alias/metabomax-hipaa"
  target_key_id = aws_kms_key.metabomax_hipaa.key_id
}

# Create separate keys for different purposes
resource "aws_kms_key" "rds_encryption" {
  description             = "RDS database encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_key" "s3_encryption" {
  description             = "S3 bucket encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}
```

### 1.5 Amazon RDS PostgreSQL Configuration

**HIPAA-Compliant RDS Setup:**
```hcl
# rds.tf
resource "aws_db_subnet_group" "metabomax_db" {
  name       = "metabomax-db-subnet-group"
  subnet_ids = [
    aws_subnet.private_db_subnet_a.id,
    aws_subnet.private_db_subnet_b.id
  ]

  tags = {
    Name       = "metabomax-db-subnet-group"
    Compliance = "HIPAA"
  }
}

resource "aws_db_instance" "metabomax_primary" {
  identifier     = "metabomax-primary"
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.medium"

  # Storage configuration
  allocated_storage     = 100
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.rds_encryption.arn

  # Database credentials (store in Secrets Manager)
  db_name  = "metabomaxpro"
  username = "metabomax_admin"
  password = data.aws_secretsmanager_secret_version.db_password.secret_string

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.metabomax_db.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false

  # Backup configuration (HIPAA requirement)
  backup_retention_period = 30
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Enable automated backups
  skip_final_snapshot     = false
  final_snapshot_identifier = "metabomax-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # High availability
  multi_az = true

  # Logging (HIPAA requirement)
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Deletion protection
  deletion_protection = true

  # Performance Insights for monitoring
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.rds_encryption.arn

  tags = {
    Name       = "metabomax-primary-db"
    Compliance = "HIPAA"
    PHI        = "true"
  }
}
```

### 1.6 Amazon S3 for PHI Storage

**S3 Bucket Configuration:**
```hcl
# s3.tf
resource "aws_s3_bucket" "metabomax_phi" {
  bucket = "metabomax-phi-storage-${var.account_id}"

  tags = {
    Name       = "metabomax-phi-storage"
    Compliance = "HIPAA"
    PHI        = "true"
  }
}

# Enable versioning (HIPAA requirement)
resource "aws_s3_bucket_versioning" "metabomax_phi" {
  bucket = aws_s3_bucket.metabomax_phi.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption (HIPAA requirement)
resource "aws_s3_bucket_server_side_encryption_configuration" "metabomax_phi" {
  bucket = aws_s3_bucket.metabomax_phi.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_encryption.arn
    }
    bucket_key_enabled = true
  }
}

# Block public access (HIPAA requirement)
resource "aws_s3_bucket_public_access_block" "metabomax_phi" {
  bucket = aws_s3_bucket.metabomax_phi.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Logging (HIPAA requirement)
resource "aws_s3_bucket_logging" "metabomax_phi" {
  bucket = aws_s3_bucket.metabomax_phi.id

  target_bucket = aws_s3_bucket.metabomax_logs.id
  target_prefix = "phi-bucket-logs/"
}

# Lifecycle policy for data retention
resource "aws_s3_bucket_lifecycle_configuration" "metabomax_phi" {
  bucket = aws_s3_bucket.metabomax_phi.id

  rule {
    id     = "archive-old-reports"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # HIPAA requires 6-year retention for PHI
    expiration {
      days = 2190  # 6 years
    }
  }
}
```

### 1.7 CloudTrail Audit Logging

**CloudTrail Configuration:**
```hcl
# cloudtrail.tf
resource "aws_cloudtrail" "metabomax_audit" {
  name                          = "metabomax-hipaa-audit-trail"
  s3_bucket_name                = aws_s3_bucket.metabomax_audit_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  # Enable CloudWatch Logs integration
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_cloudwatch.arn

  # Encrypt audit logs
  kms_key_id = aws_kms_key.cloudtrail_encryption.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.metabomax_phi.arn}/*"]
    }

    data_resource {
      type   = "AWS::RDS::DBCluster"
      values = ["*"]
    }
  }

  tags = {
    Name       = "metabomax-hipaa-audit"
    Compliance = "HIPAA"
  }
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/metabomax-hipaa"
  retention_in_days = 365  # HIPAA requires 1 year minimum
  kms_key_id        = aws_kms_key.cloudwatch_encryption.arn

  tags = {
    Name       = "metabomax-cloudtrail-logs"
    Compliance = "HIPAA"
  }
}
```

### 1.8 EC2/ECS Application Hosting

**ECS Cluster Configuration:**
```hcl
# ecs.tf
resource "aws_ecs_cluster" "metabomax" {
  name = "metabomax-hipaa-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  configuration {
    execute_command_configuration {
      kms_key_id = aws_kms_key.metabomax_hipaa.arn
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs_exec.name
      }
    }
  }

  tags = {
    Name       = "metabomax-cluster"
    Compliance = "HIPAA"
  }
}

resource "aws_ecs_task_definition" "flask_app" {
  family                   = "metabomax-flask-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "flask-app"
      image = "${aws_ecr_repository.metabomax_app.repository_url}:latest"

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "FLASK_ENV"
          value = "production"
        }
      ]

      secrets = [
        {
          name      = "FLASK_SECRET_KEY"
          valueFrom = "${aws_secretsmanager_secret.flask_secret.arn}"
        },
        {
          name      = "DATABASE_URL"
          valueFrom = "${aws_secretsmanager_secret.db_url.arn}"
        },
        {
          name      = "OPENAI_API_KEY"
          valueFrom = "${aws_secretsmanager_secret.openai_key.arn}"
        },
        {
          name      = "STRIPE_SECRET_KEY"
          valueFrom = "${aws_secretsmanager_secret.stripe_key.arn}"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.flask_app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "flask"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    Name       = "metabomax-flask-app"
    Compliance = "HIPAA"
  }
}
```

### 1.9 AWS Secrets Manager

**Secrets Management:**
```hcl
# secrets.tf
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "metabomax/database/password"
  description             = "RDS database password"
  kms_key_id              = aws_kms_key.secrets_encryption.arn
  recovery_window_in_days = 30

  tags = {
    Name       = "metabomax-db-password"
    Compliance = "HIPAA"
  }
}

resource "aws_secretsmanager_secret" "openai_key" {
  name                    = "metabomax/openai/api-key"
  description             = "OpenAI API key for AI recommendations"
  kms_key_id              = aws_kms_key.secrets_encryption.arn
  recovery_window_in_days = 30
}

# Enable automatic rotation for database credentials
resource "aws_secretsmanager_secret_rotation" "db_password" {
  secret_id           = aws_secretsmanager_secret.db_password.id
  rotation_lambda_arn = aws_lambda_function.rotate_db_password.arn

  rotation_rules {
    automatically_after_days = 90
  }
}
```

### 1.10 Application Load Balancer with TLS

**ALB Configuration:**
```hcl
# alb.tf
resource "aws_lb" "metabomax" {
  name               = "metabomax-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [
    aws_subnet.public_subnet_a.id,
    aws_subnet.public_subnet_b.id
  ]

  # Enable access logs (HIPAA requirement)
  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "metabomax-alb"
    enabled = true
  }

  # Enable deletion protection in production
  enable_deletion_protection = true

  tags = {
    Name       = "metabomax-alb"
    Compliance = "HIPAA"
  }
}

# HTTPS listener (required for HIPAA)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.metabomax.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"  # TLS 1.2 minimum
  certificate_arn   = aws_acm_certificate.metabomax.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.flask_app.arn
  }
}

# HTTP listener (redirect to HTTPS)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.metabomax.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
```

### 1.11 IAM Policies and Roles

**Least Privilege IAM Configuration:**
```hcl
# iam.tf
resource "aws_iam_role" "ecs_task_role" {
  name = "metabomax-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name       = "metabomax-ecs-task-role"
    Compliance = "HIPAA"
  }
}

# Allow S3 access for PHI storage
resource "aws_iam_role_policy" "s3_phi_access" {
  name = "s3-phi-access"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.metabomax_phi.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.s3_encryption.arn
      }
    ]
  })
}

# CloudWatch Logs access
resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "cloudwatch-logs-access"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.flask_app.arn}:*"
      }
    ]
  })
}
```

---

## Part 2: AI/Claude HIPAA Compliance

### 2.1 Anthropic Claude API HIPAA Requirements

**Anthropic HIPAA Eligibility:**
- Anthropic does NOT currently offer a BAA for Claude API usage
- Standard Claude API is NOT HIPAA compliant
- Alternative: Use Anthropic Claude via AWS Bedrock with BAA

**Critical Decision Point:**
You must choose between:

**Option A: AWS Bedrock Claude (HIPAA Compliant)**
- AWS offers BAA coverage for Bedrock services
- Claude models available via Bedrock
- Fully integrated with AWS KMS, CloudWatch, CloudTrail
- Higher cost but HIPAA compliant

**Option B: De-identify Data Before OpenAI/Claude Processing**
- Strip all PHI before sending to AI APIs
- Only send anonymized metabolic values
- Requires careful data sanitization
- More complex implementation but lower cost

### 2.2 Recommended Approach: AWS Bedrock + Claude

**Bedrock Configuration:**
```python
# app.py modifications for Bedrock
import boto3
import json

# Initialize Bedrock client
bedrock_runtime = boto3.client(
    service_name='bedrock-runtime',
    region_name='us-east-1'
)

def generate_ai_recommendations_bedrock(patient_data, focus_areas):
    """
    Generate AI recommendations using AWS Bedrock Claude
    HIPAA compliant with BAA coverage
    """
    # Prepare the prompt
    prompt = f"""
    Generate personalized health recommendations based on the following metabolic data:

    VO2 Max: {patient_data['vo2_max']} ml/kg/min
    RMR: {patient_data['rmr']} kcal
    RER: {patient_data['rer']}
    Age: {patient_data['age']}
    Sex: {patient_data['sex']}

    Focus areas: {', '.join(focus_areas)}

    Provide specific, actionable recommendations.
    """

    # Call Bedrock with Claude model
    try:
        response = bedrock_runtime.invoke_model(
            modelId='anthropic.claude-3-sonnet-20240229-v1:0',
            contentType='application/json',
            accept='application/json',
            body=json.dumps({
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 2000,
                "messages": [
                    {
                        "role": "user",
                        "content": prompt
                    }
                ]
            })
        )

        # Parse response
        response_body = json.loads(response['body'].read())
        recommendations = response_body['content'][0]['text']

        # Log the API call for audit purposes
        log_phi_access(
            action='AI_RECOMMENDATION_GENERATED',
            user_id=patient_data['user_id'],
            details=f"Generated recommendations via Bedrock Claude"
        )

        return recommendations

    except Exception as e:
        # Log the error
        log_error(f"Bedrock API error: {str(e)}")
        return None
```

**Bedrock IAM Policy:**
```hcl
# iam.tf - Add Bedrock permissions
resource "aws_iam_role_policy" "bedrock_access" {
  name = "bedrock-access"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0",
          "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-opus-20240229-v1:0"
        ]
      }
    ]
  })
}
```

### 2.3 Alternative: OpenAI with De-identification

**If continuing with OpenAI (requires data anonymization):**

```python
# utils/phi_anonymization.py
import hashlib
import re

def anonymize_phi_for_ai(patient_data):
    """
    Remove all PHI before sending to external AI APIs
    HIPAA requires complete de-identification
    """
    # Create anonymized data structure
    anonymized = {
        # Metabolic values (not considered PHI)
        'vo2_max': patient_data.get('vo2_max'),
        'rmr': patient_data.get('rmr'),
        'rer': patient_data.get('rer'),
        'heart_rate_zones': patient_data.get('heart_rate_zones'),

        # Demographic data (generalized)
        'age_range': generalize_age(patient_data.get('age')),
        'sex': patient_data.get('sex'),  # Not PHI when not combined with other identifiers

        # NO names, emails, dates, or unique identifiers
    }

    return anonymized

def generalize_age(age):
    """
    Generalize age to 5-year ranges per HIPAA Safe Harbor
    """
    if age < 20:
        return "Under 20"
    elif age > 89:
        return "90 and over"  # HIPAA requires 90+ to be grouped
    else:
        range_start = (age // 5) * 5
        return f"{range_start}-{range_start + 4}"

def validate_no_phi(data):
    """
    Validate that data contains no PHI before AI processing
    """
    # Check for patterns that might be PHI
    phi_patterns = [
        r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b',  # Email
        r'\b\d{3}-\d{2}-\d{4}\b',  # SSN
        r'\b\d{3}-\d{3}-\d{4}\b',  # Phone number
        r'\b[A-Z][a-z]+ [A-Z][a-z]+\b',  # Names
    ]

    data_str = str(data)
    for pattern in phi_patterns:
        if re.search(pattern, data_str):
            raise ValueError(f"PHI detected in data: {pattern}")

    return True
```

### 2.4 AI Audit Logging

**Comprehensive AI Usage Logging:**
```python
# utils/audit_logging.py
import boto3
import json
from datetime import datetime

cloudwatch = boto3.client('logs', region_name='us-east-1')

def log_ai_api_call(user_id, model, input_summary, output_summary, success):
    """
    Log all AI API calls for HIPAA audit compliance
    """
    log_entry = {
        'timestamp': datetime.utcnow().isoformat(),
        'event_type': 'AI_API_CALL',
        'user_id': user_id,
        'model': model,
        'input_summary': input_summary,  # Summary only, no PHI
        'output_summary': output_summary,
        'success': success,
        'compliance_note': 'PHI de-identified before processing' if model != 'bedrock' else 'BAA-covered processing'
    }

    # Send to CloudWatch Logs
    cloudwatch.put_log_events(
        logGroupName='/aws/metabomax/ai-audit',
        logStreamName=datetime.utcnow().strftime('%Y/%m/%d'),
        logEvents=[
            {
                'timestamp': int(datetime.utcnow().timestamp() * 1000),
                'message': json.dumps(log_entry)
            }
        ]
    )

    # Also store in RDS audit table
    store_audit_log_to_db(log_entry)
```

### 2.5 OpenAI BAA (if using OpenAI instead of Claude)

**OpenAI HIPAA Compliance:**
- OpenAI offers a BAA for enterprise customers
- Requires OpenAI Enterprise plan
- Contact OpenAI sales for BAA execution
- Zero data retention policy must be enabled

**OpenAI Configuration with BAA:**
```python
# app.py modifications for OpenAI with BAA
from openai import OpenAI

# Initialize OpenAI client with enterprise endpoint
client = OpenAI(
    api_key=os.environ.get('OPENAI_API_KEY'),
    organization=os.environ.get('OPENAI_ORG_ID')
)

def generate_ai_recommendations_openai(patient_data, focus_areas):
    """
    Generate AI recommendations using OpenAI with BAA coverage
    """
    try:
        response = client.chat.completions.create(
            model="gpt-4",
            messages=[
                {
                    "role": "system",
                    "content": "You are a health and fitness advisor providing personalized recommendations based on metabolic data."
                },
                {
                    "role": "user",
                    "content": f"""
                    Generate recommendations for:
                    VO2 Max: {patient_data['vo2_max']}
                    RMR: {patient_data['rmr']}
                    Focus: {', '.join(focus_areas)}
                    """
                }
            ]
        )

        recommendations = response.choices[0].message.content

        # Audit log
        log_ai_api_call(
            user_id=patient_data['user_id'],
            model='gpt-4',
            input_summary='Metabolic data for recommendations',
            output_summary='Generated recommendations',
            success=True
        )

        return recommendations

    except Exception as e:
        log_ai_api_call(
            user_id=patient_data['user_id'],
            model='gpt-4',
            input_summary='Metabolic data for recommendations',
            output_summary=str(e),
            success=False
        )
        return None
```

### 2.6 Data Retention and Deletion

**AI Data Retention Policy:**
```python
# utils/data_retention.py
from datetime import datetime, timedelta

def enforce_ai_data_retention():
    """
    HIPAA requires ability to delete PHI on request
    Ensure AI-generated content can be purged
    """
    # Delete AI recommendations older than retention period
    retention_days = 2190  # 6 years per HIPAA
    cutoff_date = datetime.utcnow() - timedelta(days=retention_days)

    # Query database for old AI recommendations
    old_recommendations = db.execute("""
        DELETE FROM ai_recommendations
        WHERE created_at < %s
        RETURNING id, user_id
    """, (cutoff_date,))

    # Log deletions
    for rec in old_recommendations:
        log_phi_access(
            action='DATA_DELETED',
            user_id=rec['user_id'],
            details=f"AI recommendation {rec['id']} deleted per retention policy"
        )

def handle_right_to_deletion(user_id):
    """
    HIPAA Right of Access - users can request data deletion
    """
    # Delete all AI-generated content for user
    deleted_count = db.execute("""
        DELETE FROM ai_recommendations
        WHERE user_id = %s
        RETURNING id
    """, (user_id,))

    # Also purge from S3 if stored there
    s3_client = boto3.client('s3')
    s3_client.delete_object(
        Bucket='metabomax-phi-storage',
        Key=f'ai-recommendations/{user_id}/'
    )

    # Audit log
    log_phi_access(
        action='USER_REQUESTED_DELETION',
        user_id=user_id,
        details=f"Deleted {len(deleted_count)} AI recommendations"
    )

    return len(deleted_count)
```

---

## Part 3: Database HIPAA Compliance

### 3.1 Supabase vs AWS RDS Decision Matrix

| Criteria | Supabase (Current) | AWS RDS PostgreSQL |
|----------|-------------------|-------------------|
| **BAA Available** | NO | YES |
| **HIPAA Compliant** | NO (unless self-hosted) | YES (with proper config) |
| **Encryption at Rest** | Yes | Yes (KMS) |
| **Encryption in Transit** | Yes (TLS) | Yes (TLS) |
| **Audit Logging** | Limited | Comprehensive (CloudTrail) |
| **Access Controls** | Basic | Advanced (IAM + DB roles) |
| **Backup/Recovery** | Automated | Automated + Point-in-time |
| **Multi-AZ** | No | Yes |
| **Cost** | Lower | Higher |
| **Migration Effort** | N/A | Significant |

**RECOMMENDATION: Migrate to AWS RDS PostgreSQL**

Supabase does not offer a BAA for their hosted service, making it non-compliant with HIPAA. You must either:
1. Self-host Supabase (complex, not recommended)
2. Migrate to AWS RDS PostgreSQL (recommended)

### 3.2 Database Migration Plan

**Phase 1: Assessment (Week 1)**
- Export current Supabase schema
- Document all tables, indexes, constraints
- Identify stored procedures and triggers
- List all database users and roles

**Phase 2: AWS RDS Setup (Week 2)**
- Create RDS instance with HIPAA configuration
- Configure security groups and network access
- Set up KMS encryption
- Enable CloudWatch logging

**Phase 3: Schema Migration (Week 3)**
- Create schema in RDS
- Migrate tables and indexes
- Migrate stored procedures
- Test database integrity

**Phase 4: Data Migration (Week 4)**
- Use `pg_dump` to export Supabase data
- Import data into RDS
- Validate data integrity
- Run data reconciliation scripts

**Phase 5: Application Update (Week 5)**
- Update Flask app database connection strings
- Replace Supabase client with psycopg2
- Update authentication to use RDS
- Test all database operations

**Phase 6: Cutover (Week 6)**
- Schedule maintenance window
- Perform final data sync
- Switch DNS/connection strings
- Monitor for issues
- Keep Supabase as read-only backup for 30 days

### 3.3 RDS Connection Configuration

**Update Flask app.py for RDS:**
```python
# app.py database configuration
import psycopg2
from psycopg2 import pool
import boto3
import json

# Get database credentials from Secrets Manager
def get_db_credentials():
    """
    Retrieve database credentials from AWS Secrets Manager
    """
    secrets_client = boto3.client('secretsmanager', region_name='us-east-1')

    try:
        response = secrets_client.get_secret_value(
            SecretId='metabomax/database/credentials'
        )
        secrets = json.loads(response['SecretString'])
        return secrets
    except Exception as e:
        print(f"Error retrieving database credentials: {str(e)}")
        raise

# Initialize connection pool
db_creds = get_db_credentials()
db_pool = psycopg2.pool.SimpleConnectionPool(
    minconn=1,
    maxconn=20,
    host=db_creds['host'],
    port=db_creds['port'],
    database=db_creds['database'],
    user=db_creds['username'],
    password=db_creds['password'],
    sslmode='require',  # Required for HIPAA
    sslrootcert='/path/to/rds-ca-cert.pem',  # AWS RDS CA certificate
    connect_timeout=10
)

def get_db_connection():
    """
    Get a connection from the pool
    """
    try:
        conn = db_pool.getconn()
        return conn
    except Exception as e:
        print(f"Error getting database connection: {str(e)}")
        raise

def release_db_connection(conn):
    """
    Return connection to pool
    """
    db_pool.putconn(conn)

# Example query with audit logging
def get_user_profile(user_id):
    """
    Retrieve user profile with HIPAA audit logging
    """
    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        # Log the access
        log_phi_access(
            action='READ',
            user_id=user_id,
            table='profiles',
            details='User profile accessed'
        )

        # Execute query
        cursor.execute("""
            SELECT id, email, full_name, date_of_birth, created_at
            FROM profiles
            WHERE id = %s
        """, (user_id,))

        profile = cursor.fetchone()
        cursor.close()
        release_db_connection(conn)

        return profile

    except Exception as e:
        cursor.close()
        release_db_connection(conn)
        log_error(f"Error retrieving user profile: {str(e)}")
        raise
```

### 3.4 Database Audit Logging

**Create audit log table:**
```sql
-- Create audit log table in RDS
CREATE TABLE phi_access_log (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    user_id UUID,
    action VARCHAR(50) NOT NULL,  -- READ, WRITE, UPDATE, DELETE
    table_name VARCHAR(100),
    record_id VARCHAR(100),
    ip_address INET,
    user_agent TEXT,
    details JSONB,
    success BOOLEAN DEFAULT true
);

-- Create index for queries
CREATE INDEX idx_phi_access_log_user_id ON phi_access_log(user_id);
CREATE INDEX idx_phi_access_log_timestamp ON phi_access_log(timestamp);
CREATE INDEX idx_phi_access_log_action ON phi_access_log(action);

-- Enable Row Level Security (RLS)
ALTER TABLE phi_access_log ENABLE ROW LEVEL SECURITY;

-- Create policy to prevent modification
CREATE POLICY phi_access_log_append_only ON phi_access_log
    FOR INSERT
    WITH CHECK (true);

CREATE POLICY phi_access_log_no_delete ON phi_access_log
    FOR DELETE
    USING (false);
```

**Audit logging function:**
```python
# utils/db_audit.py
def log_phi_access(action, user_id, table=None, record_id=None, details=None, ip_address=None, user_agent=None, success=True):
    """
    Log all PHI access for HIPAA compliance
    """
    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        cursor.execute("""
            INSERT INTO phi_access_log
            (user_id, action, table_name, record_id, ip_address, user_agent, details, success)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """, (
            user_id,
            action,
            table,
            record_id,
            ip_address,
            user_agent,
            json.dumps(details) if details else None,
            success
        ))

        conn.commit()
        cursor.close()
        release_db_connection(conn)

    except Exception as e:
        conn.rollback()
        cursor.close()
        release_db_connection(conn)
        print(f"Error logging PHI access: {str(e)}")
```

### 3.5 Database Encryption

**Enable transparent data encryption:**
```sql
-- All data encrypted at rest via KMS (configured in RDS setup)
-- Enable pg_crypto extension for application-level encryption
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Example: Encrypt sensitive fields in database
ALTER TABLE profiles
ADD COLUMN date_of_birth_encrypted BYTEA;

-- Function to encrypt sensitive data
CREATE OR REPLACE FUNCTION encrypt_sensitive_data(data TEXT, key TEXT)
RETURNS BYTEA AS $$
BEGIN
    RETURN pgp_sym_encrypt(data, key);
END;
$$ LANGUAGE plpgsql;

-- Function to decrypt sensitive data
CREATE OR REPLACE FUNCTION decrypt_sensitive_data(encrypted_data BYTEA, key TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN pgp_sym_decrypt(encrypted_data, key);
END;
$$ LANGUAGE plpgsql;
```

**Application-level encryption:**
```python
# utils/encryption.py
from cryptography.fernet import Fernet
import boto3
import base64

def get_encryption_key():
    """
    Retrieve encryption key from AWS Secrets Manager
    """
    secrets_client = boto3.client('secretsmanager', region_name='us-east-1')
    response = secrets_client.get_secret_value(SecretId='metabomax/encryption/key')
    key = response['SecretString']
    return key.encode()

def encrypt_field(data):
    """
    Encrypt sensitive field before storing in database
    """
    key = get_encryption_key()
    f = Fernet(key)
    encrypted = f.encrypt(data.encode())
    return base64.b64encode(encrypted).decode()

def decrypt_field(encrypted_data):
    """
    Decrypt sensitive field when retrieving from database
    """
    key = get_encryption_key()
    f = Fernet(key)
    decoded = base64.b64decode(encrypted_data)
    decrypted = f.decrypt(decoded)
    return decrypted.decode()

# Usage in app.py
def save_user_profile(user_id, profile_data):
    """
    Save user profile with encrypted sensitive fields
    """
    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        # Encrypt date of birth
        dob_encrypted = encrypt_field(profile_data['date_of_birth'])

        cursor.execute("""
            INSERT INTO profiles (id, email, full_name, date_of_birth_encrypted)
            VALUES (%s, %s, %s, %s)
        """, (
            user_id,
            profile_data['email'],
            profile_data['full_name'],
            dob_encrypted
        ))

        conn.commit()

        # Audit log
        log_phi_access(
            action='WRITE',
            user_id=user_id,
            table='profiles',
            details='User profile created with encrypted DOB'
        )

        cursor.close()
        release_db_connection(conn)

    except Exception as e:
        conn.rollback()
        cursor.close()
        release_db_connection(conn)
        raise
```

### 3.6 Database Backup and Recovery

**Automated backup configuration (already in RDS setup):**
```hcl
# Additional backup configuration
resource "aws_db_instance_automated_backups_replication" "metabomax" {
  source_db_instance_arn = aws_db_instance.metabomax_primary.arn
  retention_period       = 30
  kms_key_id             = aws_kms_key.backup_encryption.arn

  # Replicate backups to different region for disaster recovery
  depends_on = [aws_db_instance.metabomax_primary]
}

# Create read replica in different AZ
resource "aws_db_instance" "metabomax_replica" {
  identifier             = "metabomax-replica"
  replicate_source_db    = aws_db_instance.metabomax_primary.identifier
  instance_class         = "db.t3.medium"
  publicly_accessible    = false
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.rds_encryption.arn
  backup_retention_period = 30

  tags = {
    Name       = "metabomax-replica-db"
    Compliance = "HIPAA"
  }
}
```

**Backup verification script:**
```python
# utils/backup_verification.py
import boto3
from datetime import datetime, timedelta

def verify_recent_backup():
    """
    HIPAA requires verification of backup integrity
    """
    rds_client = boto3.client('rds', region_name='us-east-1')

    # Get recent automated backups
    response = rds_client.describe_db_snapshots(
        DBInstanceIdentifier='metabomax-primary',
        SnapshotType='automated',
        MaxRecords=5
    )

    snapshots = response['DBSnapshots']

    if not snapshots:
        log_error("No automated backups found!")
        return False

    # Check if backup is recent (within 24 hours)
    latest_backup = snapshots[0]
    backup_time = latest_backup['SnapshotCreateTime']
    age = datetime.now(backup_time.tzinfo) - backup_time

    if age > timedelta(hours=24):
        log_error(f"Latest backup is {age.total_seconds() / 3600:.1f} hours old!")
        return False

    # Log successful verification
    log_phi_access(
        action='BACKUP_VERIFIED',
        user_id='SYSTEM',
        details=f"Backup {latest_backup['DBSnapshotIdentifier']} verified"
    )

    return True

# Run daily via cron or Lambda
if __name__ == '__main__':
    if not verify_recent_backup():
        # Send alert to administrators
        send_alert("Backup verification failed!")
```

### 3.7 Database Access Controls

**Implement strict database roles:**
```sql
-- Create application role with limited permissions
CREATE ROLE metabomax_app WITH LOGIN PASSWORD 'strong_password';

-- Grant minimal permissions
GRANT CONNECT ON DATABASE metabomaxpro TO metabomax_app;
GRANT USAGE ON SCHEMA public TO metabomax_app;

-- Grant specific table permissions
GRANT SELECT, INSERT, UPDATE ON profiles TO metabomax_app;
GRANT SELECT, INSERT, UPDATE ON metabolic_tests TO metabomax_app;
GRANT SELECT, INSERT, UPDATE ON reports TO metabomax_app;
GRANT SELECT, INSERT, UPDATE ON subscriptions TO metabomax_app;

-- Audit log table is append-only
GRANT INSERT ON phi_access_log TO metabomax_app;
GRANT SELECT ON phi_access_log TO metabomax_app;

-- Read-only role for reporting/analytics
CREATE ROLE metabomax_readonly WITH LOGIN PASSWORD 'strong_password';
GRANT CONNECT ON DATABASE metabomaxpro TO metabomax_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO metabomax_readonly;

-- Admin role (use sparingly)
CREATE ROLE metabomax_admin WITH LOGIN PASSWORD 'strong_password' SUPERUSER;
```

---

## Part 4: Application-Level HIPAA Requirements

### 4.1 Authentication and Authorization

**Multi-factor authentication requirement:**
```python
# app.py - Add MFA requirement
from pyotp import TOTP
import qrcode
from io import BytesIO

@app.route('/setup-mfa', methods=['GET', 'POST'])
@login_required
def setup_mfa():
    """
    HIPAA recommends MFA for PHI access
    """
    user_id = session['user_id']

    if request.method == 'GET':
        # Generate TOTP secret
        secret = pyotp.random_base32()

        # Store secret in database (encrypted)
        save_mfa_secret(user_id, secret)

        # Generate QR code
        totp_uri = pyotp.totp.TOTP(secret).provisioning_uri(
            name=session['user_email'],
            issuer_name='MetaboMax Pro'
        )

        qr = qrcode.QRCode(version=1, box_size=10, border=5)
        qr.add_data(totp_uri)
        qr.make(fit=True)
        img = qr.make_image(fill_color="black", back_color="white")

        # Convert to base64 for display
        buffer = BytesIO()
        img.save(buffer, format='PNG')
        img_str = base64.b64encode(buffer.getvalue()).decode()

        return render_template('setup_mfa.html', qr_code=img_str, secret=secret)

    elif request.method == 'POST':
        # Verify MFA code
        code = request.form.get('code')
        secret = get_mfa_secret(user_id)

        totp = TOTP(secret)
        if totp.verify(code):
            # Mark MFA as enabled
            enable_mfa(user_id)

            log_phi_access(
                action='MFA_ENABLED',
                user_id=user_id,
                details='Multi-factor authentication enabled'
            )

            flash('Multi-factor authentication enabled successfully!')
            return redirect(url_for('dashboard'))
        else:
            flash('Invalid verification code. Please try again.')
            return redirect(url_for('setup_mfa'))

@app.route('/login', methods=['POST'])
def login():
    """
    Enhanced login with MFA check
    """
    email = request.form.get('email')
    password = request.form.get('password')

    # Verify credentials
    user = verify_credentials(email, password)

    if not user:
        log_phi_access(
            action='LOGIN_FAILED',
            user_id=None,
            details=f'Failed login attempt for {email}',
            ip_address=request.remote_addr
        )
        return jsonify({'error': 'Invalid credentials'}), 401

    # Check if MFA is enabled
    if user['mfa_enabled']:
        # Store user ID in session temporarily
        session['pending_mfa_user_id'] = user['id']
        return jsonify({'mfa_required': True})

    # No MFA, complete login
    complete_login(user)
    return jsonify({'success': True})

@app.route('/verify-mfa', methods=['POST'])
def verify_mfa():
    """
    Verify MFA code during login
    """
    user_id = session.get('pending_mfa_user_id')
    if not user_id:
        return jsonify({'error': 'No pending MFA verification'}), 400

    code = request.form.get('code')
    secret = get_mfa_secret(user_id)

    totp = TOTP(secret)
    if totp.verify(code):
        # MFA verified, complete login
        user = get_user_by_id(user_id)
        complete_login(user)

        # Clear pending MFA
        session.pop('pending_mfa_user_id', None)

        log_phi_access(
            action='LOGIN_SUCCESS',
            user_id=user_id,
            details='Successful login with MFA',
            ip_address=request.remote_addr
        )

        return jsonify({'success': True})
    else:
        log_phi_access(
            action='MFA_FAILED',
            user_id=user_id,
            details='Failed MFA verification',
            ip_address=request.remote_addr
        )
        return jsonify({'error': 'Invalid MFA code'}), 401
```

### 4.2 Session Management

**Secure session configuration:**
```python
# app.py session configuration
from datetime import timedelta

app.config['SECRET_KEY'] = os.environ.get('FLASK_SECRET_KEY')
app.config['SESSION_COOKIE_SECURE'] = True  # HTTPS only
app.config['SESSION_COOKIE_HTTPONLY'] = True  # No JavaScript access
app.config['SESSION_COOKIE_SAMESITE'] = 'Lax'  # CSRF protection
app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(minutes=30)  # 30-minute timeout

# Session timeout middleware
@app.before_request
def check_session_timeout():
    """
    HIPAA recommends automatic session timeout
    """
    if 'user_id' in session:
        last_activity = session.get('last_activity')

        if last_activity:
            # Check if session has expired
            timeout_minutes = 30
            if datetime.utcnow() - last_activity > timedelta(minutes=timeout_minutes):
                # Log timeout
                log_phi_access(
                    action='SESSION_TIMEOUT',
                    user_id=session['user_id'],
                    details=f'Session timed out after {timeout_minutes} minutes'
                )

                # Clear session
                session.clear()
                flash('Your session has expired. Please log in again.')
                return redirect(url_for('login'))

        # Update last activity
        session['last_activity'] = datetime.utcnow()
```

### 4.3 Data Minimization

**Collect only necessary PHI:**
```python
# app.py - Update registration to minimize data collection
@app.route('/register', methods=['POST'])
def register():
    """
    Registration with data minimization principle
    Only collect necessary information
    """
    # Required fields only
    email = request.form.get('email')
    password = request.form.get('password')

    # Optional fields (clearly marked)
    full_name = request.form.get('full_name', None)  # Optional
    date_of_birth = request.form.get('date_of_birth', None)  # Optional, needed for biological age

    # Validate required fields
    if not email or not password:
        return jsonify({'error': 'Email and password are required'}), 400

    # Create user account
    user_id = create_user(email, password, full_name, date_of_birth)

    # Log registration
    log_phi_access(
        action='USER_REGISTERED',
        user_id=user_id,
        details='New user account created',
        ip_address=request.remote_addr
    )

    return jsonify({'success': True, 'user_id': user_id})
```

### 4.4 Breach Notification System

**Automated breach detection and notification:**
```python
# utils/breach_notification.py
from datetime import datetime
import boto3

sns_client = boto3.client('sns', region_name='us-east-1')

def detect_unusual_access(user_id):
    """
    Detect potentially unauthorized access patterns
    """
    conn = get_db_connection()
    cursor = conn.cursor()

    # Check for unusual access patterns
    cursor.execute("""
        SELECT COUNT(*) as access_count,
               COUNT(DISTINCT ip_address) as unique_ips,
               MAX(timestamp) as last_access
        FROM phi_access_log
        WHERE user_id = %s
          AND timestamp > NOW() - INTERVAL '1 hour'
    """, (user_id,))

    result = cursor.fetchone()
    cursor.close()
    release_db_connection(conn)

    # Alert if suspicious activity
    if result['access_count'] > 100 or result['unique_ips'] > 10:
        trigger_breach_investigation(user_id, result)
        return True

    return False

def trigger_breach_investigation(user_id, access_data):
    """
    Initiate breach investigation process
    HIPAA requires notification within 60 days
    """
    # Create incident record
    incident_id = create_incident_record(
        user_id=user_id,
        incident_type='UNUSUAL_ACCESS',
        severity='HIGH',
        details=access_data
    )

    # Notify security team
    sns_client.publish(
        TopicArn='arn:aws:sns:us-east-1:ACCOUNT_ID:security-alerts',
        Subject='HIPAA Security Incident - Unusual Access Detected',
        Message=f"""
        Unusual access pattern detected for user {user_id}

        Access count: {access_data['access_count']}
        Unique IPs: {access_data['unique_ips']}
        Last access: {access_data['last_access']}

        Incident ID: {incident_id}

        Action Required: Investigate within 24 hours per HIPAA breach notification rule.
        """
    )

    # Log the incident
    log_phi_access(
        action='SECURITY_INCIDENT',
        user_id=user_id,
        details=f'Incident {incident_id} - Unusual access pattern detected'
    )

def notify_affected_users(incident_id):
    """
    Notify users if breach is confirmed
    HIPAA requires notification within 60 days
    """
    # Get affected users
    affected_users = get_incident_affected_users(incident_id)

    for user in affected_users:
        # Send email notification
        send_breach_notification_email(
            user_email=user['email'],
            incident_date=user['incident_date'],
            data_affected='Metabolic test results and personal health information'
        )

        # Log notification
        log_phi_access(
            action='BREACH_NOTIFICATION_SENT',
            user_id=user['id'],
            details=f'User notified of security incident {incident_id}'
        )

    # Notify HHS if >500 individuals affected
    if len(affected_users) > 500:
        notify_hhs_breach(incident_id, affected_users)
```

### 4.5 Business Associate Agreements

**Track all business associates:**
```python
# utils/business_associates.py

BUSINESS_ASSOCIATES = {
    'aws': {
        'name': 'Amazon Web Services',
        'baa_signed': True,
        'baa_date': '2024-01-15',
        'services': ['EC2', 'RDS', 'S3', 'KMS', 'CloudWatch', 'Bedrock'],
        'phi_access': True
    },
    'stripe': {
        'name': 'Stripe Inc',
        'baa_signed': False,  # Stripe is not a business associate (no PHI access)
        'services': ['Payment Processing'],
        'phi_access': False
    },
    'openai': {
        'name': 'OpenAI',
        'baa_signed': False,  # Requires enterprise plan
        'services': ['AI Recommendations'],
        'phi_access': True,  # If using without de-identification
        'status': 'NEEDS_BAA'
    },
    'anthropic': {
        'name': 'Anthropic (via AWS Bedrock)',
        'baa_signed': True,  # Covered by AWS BAA
        'services': ['AI Recommendations'],
        'phi_access': True
    }
}

def verify_baa_coverage():
    """
    Verify all services with PHI access have BAA
    """
    missing_baa = []

    for vendor_id, vendor in BUSINESS_ASSOCIATES.items():
        if vendor['phi_access'] and not vendor['baa_signed']:
            missing_baa.append(vendor)

    if missing_baa:
        # Alert administrators
        alert_message = "BAA COMPLIANCE ALERT\n\n"
        alert_message += "The following vendors have PHI access but no BAA:\n\n"

        for vendor in missing_baa:
            alert_message += f"- {vendor['name']}: {', '.join(vendor['services'])}\n"

        send_admin_alert(alert_message)
        return False

    return True
```

---

## Part 5: Implementation Roadmap

### Phase 1: Infrastructure Setup (Weeks 1-4)

**Week 1: AWS Account & BAA**
- [ ] Create AWS account (if needed)
- [ ] Sign AWS BAA via AWS Artifact
- [ ] Enable HIPAA-eligible services
- [ ] Set up billing alerts
- [ ] Create IAM users for team

**Week 2: Network & Security**
- [ ] Create VPC with public/private subnets
- [ ] Configure security groups
- [ ] Set up NAT gateways
- [ ] Configure Network ACLs
- [ ] Set up VPN access for administrators

**Week 3: Encryption & Key Management**
- [ ] Create KMS keys for different purposes
- [ ] Set up key rotation
- [ ] Configure CloudTrail with encryption
- [ ] Set up CloudWatch log groups

**Week 4: Database Migration Planning**
- [ ] Export Supabase schema
- [ ] Document all database dependencies
- [ ] Plan migration strategy
- [ ] Set up RDS instance

### Phase 2: Database Migration (Weeks 5-8)

**Week 5: RDS Setup**
- [ ] Create RDS instance with HIPAA configuration
- [ ] Configure automated backups
- [ ] Set up read replica
- [ ] Configure security groups
- [ ] Enable CloudWatch monitoring

**Week 6: Schema Migration**
- [ ] Create schema in RDS
- [ ] Migrate tables
- [ ] Migrate indexes and constraints
- [ ] Test database integrity
- [ ] Create audit logging tables

**Week 7: Data Migration**
- [ ] Export data from Supabase
- [ ] Import data to RDS
- [ ] Validate data integrity
- [ ] Run reconciliation scripts
- [ ] Test queries

**Week 8: Application Migration**
- [ ] Update database connection code
- [ ] Replace Supabase client with psycopg2
- [ ] Implement connection pooling
- [ ] Test all database operations
- [ ] Update environment variables

### Phase 3: Application Security (Weeks 9-12)

**Week 9: Authentication Enhancements**
- [ ] Implement MFA
- [ ] Add session timeout
- [ ] Implement password policies
- [ ] Add account lockout
- [ ] Update login UI

**Week 10: Audit Logging**
- [ ] Implement PHI access logging
- [ ] Create audit log dashboard
- [ ] Set up automated log analysis
- [ ] Configure log retention
- [ ] Test audit log queries

**Week 11: Encryption**
- [ ] Implement field-level encryption
- [ ] Encrypt existing sensitive data
- [ ] Update application code for encryption/decryption
- [ ] Test encrypted data retrieval
- [ ] Document encryption keys

**Week 12: AI Compliance**
- [ ] Migrate to AWS Bedrock (or implement de-identification)
- [ ] Update AI recommendation code
- [ ] Implement AI audit logging
- [ ] Test AI recommendations
- [ ] Document AI data flow

### Phase 4: Testing & Validation (Weeks 13-14)

**Week 13: Security Testing**
- [ ] Penetration testing
- [ ] Vulnerability scanning
- [ ] Access control testing
- [ ] Encryption validation
- [ ] Audit log verification

**Week 14: Compliance Audit**
- [ ] Review all HIPAA requirements
- [ ] Document compliance controls
- [ ] Create compliance checklist
- [ ] Internal compliance audit
- [ ] Address any gaps

### Phase 5: Deployment (Weeks 15-16)

**Week 15: Pre-Production**
- [ ] Deploy to staging environment
- [ ] Full regression testing
- [ ] Performance testing
- [ ] User acceptance testing
- [ ] Create rollback plan

**Week 16: Production Deployment**
- [ ] Schedule maintenance window
- [ ] Deploy to production
- [ ] Monitor for issues
- [ ] Verify all systems operational
- [ ] Update documentation

### Phase 6: Post-Deployment (Week 17+)

**Ongoing:**
- [ ] Monitor audit logs daily
- [ ] Review access patterns weekly
- [ ] Conduct security reviews monthly
- [ ] Update risk assessments quarterly
- [ ] Annual HIPAA compliance audit

---

## Part 6: Cost Estimation

### AWS Infrastructure Costs (Monthly)

| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| EC2/ECS | 2x t3.medium (Fargate) | $60 |
| RDS PostgreSQL | db.t3.medium, Multi-AZ | $120 |
| S3 Storage | 100GB PHI storage | $3 |
| KMS | 4 customer managed keys | $4 |
| CloudTrail | Management + data events | $10 |
| CloudWatch | Logs + metrics | $20 |
| Application Load Balancer | Standard | $25 |
| Data Transfer | 500GB/month | $45 |
| Secrets Manager | 10 secrets | $4 |
| **Total Infrastructure** | | **~$291/month** |

### Additional Costs

| Item | Cost |
|------|------|
| AWS Bedrock (Claude) | $0.0015/1K input tokens, $0.0075/1K output tokens |
| Domain & SSL | $12/year (AWS Certificate Manager is free) |
| Backup Storage | $0.095/GB/month (included in estimate) |
| **Estimated AI Costs** | $100-300/month (depends on usage) |

**Total Monthly Cost: $400-600**

**Cost Comparison:**
- Current (Render + Supabase): ~$100-150/month
- HIPAA-Compliant AWS: ~$400-600/month
- **Additional Cost: $250-450/month**

---

## Part 7: Compliance Checklist

### HIPAA Security Rule Requirements

#### Administrative Safeguards
- [x] Security Management Process
  - [ ] Risk analysis completed
  - [ ] Risk management strategy implemented
  - [ ] Sanction policy for violations
  - [ ] Information system activity review (audit logs)

- [x] Security Personnel
  - [ ] Designate security official
  - [ ] Document security responsibilities

- [x] Workforce Security
  - [ ] Authorization procedures
  - [ ] Workforce clearance procedures
  - [ ] Termination procedures (revoke access)

- [x] Information Access Management
  - [ ] Implement access controls
  - [ ] Role-based access control (RBAC)
  - [ ] Principle of least privilege

- [x] Security Awareness and Training
  - [ ] Security reminders for staff
  - [ ] Protection from malware
  - [ ] Log-in monitoring
  - [ ] Password management training

- [x] Security Incident Procedures
  - [ ] Incident response plan
  - [ ] Breach notification procedures
  - [ ] Incident documentation

- [x] Contingency Plan
  - [ ] Data backup plan
  - [ ] Disaster recovery plan
  - [ ] Emergency mode operation plan
  - [ ] Testing and revision procedures

- [x] Business Associate Agreements
  - [ ] AWS BAA signed
  - [ ] Anthropic/AWS Bedrock covered by AWS BAA
  - [ ] All vendors with PHI access have BAA

#### Physical Safeguards
- [x] Facility Access Controls
  - [x] AWS data centers (covered by AWS)
  - [ ] Office physical security (if applicable)

- [x] Workstation Security
  - [ ] Encrypted laptops for staff
  - [ ] Screen locks
  - [ ] Clean desk policy

- [x] Device and Media Controls
  - [ ] Disposal procedures for hardware
  - [ ] Media re-use procedures
  - [ ] Data backup procedures

#### Technical Safeguards
- [x] Access Control
  - [ ] Unique user identification (UUID)
  - [ ] Emergency access procedures
  - [ ] Automatic logoff (session timeout)
  - [ ] Encryption and decryption (KMS)

- [x] Audit Controls
  - [ ] PHI access logging implemented
  - [ ] CloudTrail enabled
  - [ ] CloudWatch monitoring
  - [ ] Regular audit log review

- [x] Integrity
  - [ ] Data integrity validation
  - [ ] Checksums for data transmission
  - [ ] Database constraints

- [x] Person or Entity Authentication
  - [ ] Multi-factor authentication
  - [ ] Strong password requirements
  - [ ] Session management

- [x] Transmission Security
  - [ ] TLS 1.2+ for all connections
  - [ ] VPN for administrative access
  - [ ] Encrypted data in transit

### HIPAA Privacy Rule Requirements

- [ ] Notice of Privacy Practices (NPP) published on website
- [ ] Patient rights to access PHI implemented
- [ ] Patient rights to request amendments
- [ ] Patient rights to accounting of disclosures
- [ ] Minimum necessary standard implemented
- [ ] Data use and disclosure tracking
- [ ] Patient consent forms
- [ ] Privacy official designated

---

## Part 8: Documentation Requirements

### Required Documentation

1. **HIPAA Policies and Procedures Manual**
   - Security policies
   - Privacy policies
   - Incident response procedures
   - Breach notification procedures
   - Data retention and disposal
   - Employee training requirements

2. **Risk Assessment Documentation**
   - Threat identification
   - Vulnerability assessment
   - Likelihood and impact analysis
   - Risk mitigation strategies
   - Residual risk acceptance

3. **System Security Plan**
   - System architecture diagram
   - Data flow diagrams
   - Security controls documentation
   - Encryption methods
   - Access control policies

4. **Audit Log Review Documentation**
   - Review schedule
   - Review procedures
   - Findings and remediation
   - Sign-off by security official

5. **Business Associate Agreements**
   - AWS BAA
   - Any other vendor BAAs
   - BAA tracking spreadsheet

6. **Training Records**
   - Employee training completion
   - Training materials
   - Annual training schedule

7. **Incident Response Documentation**
   - Incident response plan
   - Incident log
   - Breach notification templates
   - Post-incident reviews

8. **Disaster Recovery Plan**
   - Backup procedures
   - Recovery time objectives (RTO)
   - Recovery point objectives (RPO)
   - Testing results

---

## Part 9: Next Steps

### Immediate Actions (This Week)

1. **Sign AWS BAA**
   - Create AWS account if needed
   - Navigate to AWS Artifact
   - Download and sign BAA
   - **Priority: CRITICAL**

2. **Audit Current Data**
   - Identify all PHI in current system
   - Document data locations
   - Assess compliance gaps
   - **Priority: HIGH**

3. **Designate Security Official**
   - Assign HIPAA security officer
   - Document responsibilities
   - Create communication plan
   - **Priority: HIGH**

### Short-term Actions (Next 30 Days)

1. **Infrastructure Planning**
   - Design AWS architecture
   - Create Terraform configurations
   - Estimate costs
   - Get budget approval

2. **Database Migration Planning**
   - Export Supabase schema
   - Plan migration approach
   - Schedule migration window
   - Communicate to users

3. **Policy Development**
   - Draft HIPAA policies
   - Create training materials
   - Develop incident response plan
   - Create breach notification procedures

### Medium-term Actions (60-90 Days)

1. **Execute Migration**
   - Set up AWS infrastructure
   - Migrate database
   - Update application code
   - Test thoroughly

2. **Security Enhancements**
   - Implement MFA
   - Add audit logging
   - Encrypt sensitive data
   - Deploy to production

3. **Compliance Documentation**
   - Complete risk assessment
   - Document security controls
   - Create compliance manual
   - Prepare for audit

### Long-term Actions (6+ Months)

1. **Continuous Monitoring**
   - Daily audit log review
   - Weekly security reports
   - Monthly compliance reviews
   - Quarterly risk assessments

2. **Training and Awareness**
   - Quarterly staff training
   - Annual HIPAA certification
   - Security awareness campaigns
   - Incident response drills

3. **Compliance Audits**
   - Annual HIPAA audit
   - Penetration testing
   - Vulnerability assessments
   - Update policies as needed

---

## Part 10: Risk Assessment

### High-Risk Areas

1. **Current Non-Compliance**
   - **Risk**: Supabase without BAA
   - **Impact**: HIPAA violation, potential fines
   - **Mitigation**: Urgent migration to AWS RDS
   - **Priority**: CRITICAL

2. **AI Processing Without BAA**
   - **Risk**: OpenAI API without BAA sends PHI
   - **Impact**: HIPAA violation, potential fines
   - **Mitigation**: Migrate to AWS Bedrock or implement de-identification
   - **Priority**: CRITICAL

3. **Render.com Hosting**
   - **Risk**: Hosting platform without BAA
   - **Impact**: HIPAA violation
   - **Mitigation**: Migrate to AWS ECS/EC2
   - **Priority**: CRITICAL

### Medium-Risk Areas

1. **Lack of MFA**
   - **Risk**: Unauthorized account access
   - **Impact**: PHI breach
   - **Mitigation**: Implement MFA
   - **Priority**: HIGH

2. **Limited Audit Logging**
   - **Risk**: Cannot detect unauthorized access
   - **Impact**: Delayed breach detection
   - **Mitigation**: Implement comprehensive audit logging
   - **Priority**: HIGH

3. **No Breach Notification Process**
   - **Risk**: Cannot comply with breach notification rule
   - **Impact**: Additional HIPAA penalties
   - **Mitigation**: Create breach notification procedures
   - **Priority**: HIGH

### Low-Risk Areas

1. **Password Complexity**
   - **Risk**: Weak passwords
   - **Impact**: Account compromise
   - **Mitigation**: Implement password requirements
   - **Priority**: MEDIUM

2. **Session Timeouts**
   - **Risk**: Abandoned sessions
   - **Impact**: Unauthorized access
   - **Mitigation**: Implement automatic timeout
   - **Priority**: MEDIUM

---

## Conclusion

Achieving HIPAA compliance for MetaboMax Pro requires significant architectural changes, primarily:

1. **Migrating from Render.com to AWS** with a signed BAA
2. **Migrating from Supabase to AWS RDS** PostgreSQL
3. **Migrating from OpenAI API to AWS Bedrock** (or implementing de-identification)
4. **Implementing comprehensive security controls** including MFA, audit logging, encryption, and access controls

**Estimated Timeline**: 16 weeks (4 months)
**Estimated Cost**: $400-600/month ongoing + $5,000-10,000 implementation costs
**Resources Required**: 1-2 developers, 1 security consultant

The good news is that the current codebase is well-structured and can be adapted to AWS infrastructure without major rewrites. The Flask application, report generation logic, and frontend can remain largely unchanged.

**Next Step**: Review this plan with your team and stakeholders, then begin with Phase 1 (signing AWS BAA and infrastructure planning).

---

## Appendix A: Terraform Complete Configuration

See separate files:
- `terraform/vpc.tf`
- `terraform/rds.tf`
- `terraform/s3.tf`
- `terraform/kms.tf`
- `terraform/ecs.tf`
- `terraform/alb.tf`
- `terraform/cloudtrail.tf`
- `terraform/iam.tf`
- `terraform/secrets.tf`

## Appendix B: Database Migration Scripts

See separate file: `scripts/migrate_supabase_to_rds.py`

## Appendix C: Application Code Changes

See separate file: `docs/APPLICATION_CODE_CHANGES.md`

## Appendix D: HIPAA Compliance Manual

See separate file: `docs/HIPAA_COMPLIANCE_MANUAL.md`

---

**Document Version**: 1.0
**Last Updated**: 2024-12-09
**Author**: Claude Code
**Classification**: INTERNAL USE ONLY
