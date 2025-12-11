# MetaboMax Pro HIPAA Infrastructure - Terraform

This directory contains Terraform configurations for deploying a HIPAA-compliant infrastructure for MetaboMax Pro on AWS.

## Prerequisites

1. AWS Account with BAA signed via AWS Artifact
2. AWS CLI configured with appropriate credentials
3. Terraform >= 1.0 installed
4. S3 bucket for Terraform state (see setup instructions below)

## Initial Setup

### 1. Create Terraform State Backend

Before running Terraform, create the S3 bucket and DynamoDB table for state management:

```bash
# Create S3 bucket for Terraform state
aws s3api create-bucket \
  --bucket metabomax-terraform-state \
  --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket metabomax-terraform-state \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket metabomax-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket metabomax-terraform-state \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 2. Create terraform.tfvars

Create a `terraform.tfvars` file with your specific values:

```hcl
aws_region  = "us-east-1"
account_id  = "YOUR_AWS_ACCOUNT_ID"
environment = "production"

db_username = "metabomax_admin"
db_password = "STRONG_RANDOM_PASSWORD"  # Use a password manager
db_name     = "metabomaxpro"

domain_name = "metabomaxpro.com"

enable_multi_az             = true
enable_deletion_protection  = true
backup_retention_days       = 30
log_retention_days          = 365
```

**IMPORTANT**: Never commit `terraform.tfvars` to version control. Add it to `.gitignore`.

### 3. Initialize Terraform

```bash
cd terraform
terraform init
```

### 4. Plan Infrastructure

Review what Terraform will create:

```bash
terraform plan
```

### 5. Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted to confirm.

## Infrastructure Components

This Terraform configuration deploys:

1. **VPC** - Virtual Private Cloud with public/private subnets
2. **RDS PostgreSQL** - HIPAA-compliant database with encryption
3. **S3** - Encrypted storage for PHI
4. **KMS** - Encryption key management
5. **ECS** - Container orchestration for Flask app
6. **ALB** - Application Load Balancer with TLS
7. **CloudTrail** - Audit logging
8. **CloudWatch** - Monitoring and logging
9. **Secrets Manager** - Secure credential storage
10. **IAM** - Roles and policies with least privilege

## File Structure

```
terraform/
├── main.tf              # Main configuration and backend
├── variables.tf         # Variable definitions
├── vpc.tf               # VPC and networking
├── rds.tf               # RDS PostgreSQL
├── s3.tf                # S3 buckets
├── kms.tf               # KMS keys
├── ecs.tf               # ECS cluster and tasks
├── alb.tf               # Application Load Balancer
├── cloudtrail.tf        # CloudTrail audit logging
├── iam.tf               # IAM roles and policies
├── secrets.tf           # Secrets Manager
├── security_groups.tf   # Security group rules
├── cloudwatch.tf        # CloudWatch logs and metrics
└── README.md            # This file
```

## Deployment Stages

### Stage 1: Core Infrastructure
```bash
# Deploy VPC, KMS, and CloudTrail first
terraform apply -target=aws_vpc.metabomax_vpc
terraform apply -target=aws_kms_key.metabomax_hipaa
terraform apply -target=aws_cloudtrail.metabomax_audit
```

### Stage 2: Database
```bash
# Deploy RDS
terraform apply -target=aws_db_instance.metabomax_primary
```

### Stage 3: Application Infrastructure
```bash
# Deploy ECS and ALB
terraform apply -target=aws_ecs_cluster.metabomax
terraform apply -target=aws_lb.metabomax
```

### Stage 4: Full Deployment
```bash
# Deploy everything
terraform apply
```

## Updating Infrastructure

To update the infrastructure:

```bash
# Review changes
terraform plan

# Apply changes
terraform apply
```

## Destroying Infrastructure

**WARNING**: This will delete all resources, including databases and stored data.

```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy (requires confirmation)
terraform destroy
```

## Security Considerations

1. **State File Security**
   - State file contains sensitive information
   - Stored in encrypted S3 bucket
   - Access controlled via IAM

2. **Credentials**
   - Never hardcode credentials in .tf files
   - Use Secrets Manager for application secrets
   - Use IAM roles for service authentication

3. **Network Security**
   - Database in private subnets only
   - Application in private subnets
   - ALB in public subnets
   - Security groups restrict access

4. **Encryption**
   - All data encrypted at rest (KMS)
   - All data encrypted in transit (TLS)
   - Encryption keys rotated automatically

## Monitoring and Compliance

### CloudWatch Dashboards

After deployment, access CloudWatch dashboards:
- https://console.aws.amazon.com/cloudwatch/

### CloudTrail Logs

View audit logs:
- https://console.aws.amazon.com/cloudtrail/

### Compliance Checks

Run AWS Config rules for HIPAA compliance:
```bash
aws configservice describe-compliance-by-config-rule
```

## Cost Optimization

### Development Environment

For development, use smaller instance sizes:

```hcl
# In terraform.tfvars
environment         = "development"
db_instance_class   = "db.t3.micro"
enable_multi_az     = false
app_cpu             = "256"
app_memory          = "512"
```

### Production Environment

For production, use recommended sizes:

```hcl
# In terraform.tfvars
environment         = "production"
db_instance_class   = "db.t3.medium"
enable_multi_az     = true
app_cpu             = "512"
app_memory          = "1024"
```

## Troubleshooting

### State Lock Error

If Terraform state is locked:

```bash
# View lock info
aws dynamodb get-item \
  --table-name terraform-state-lock \
  --key '{"LockID":{"S":"metabomax-terraform-state/hipaa-infrastructure/terraform.tfstate"}}'

# Force unlock (use with caution)
terraform force-unlock LOCK_ID
```

### RDS Creation Timeout

RDS instances can take 10-15 minutes to create. If you encounter a timeout:

```bash
# Increase timeout in rds.tf
resource "aws_db_instance" "metabomax_primary" {
  # ...
  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}
```

### Permission Errors

Ensure your AWS credentials have necessary permissions:

```bash
# Test AWS access
aws sts get-caller-identity

# Verify required permissions
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT_ID:user/YOUR_USER \
  --action-names ec2:CreateVpc rds:CreateDBInstance s3:CreateBucket
```

## Support and Documentation

- [AWS HIPAA Compliance](https://aws.amazon.com/compliance/hipaa-compliance/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

## Compliance Certification

After infrastructure deployment:

1. Complete HIPAA risk assessment
2. Document all security controls
3. Conduct penetration testing
4. Perform compliance audit
5. Maintain audit logs for 6 years

## Contact

For questions or issues with this infrastructure:
- Review the main HIPAA Compliance Plan
- Check AWS documentation
- Contact AWS Support for infrastructure issues
