# MetaboMax Pro HIPAA Compliance - Quick Start Guide

## CRITICAL: Current Status

**You are NOT currently HIPAA compliant.**

Your platform processes Protected Health Information (PHI) but:
- Hosted on Render.com (no BAA)
- Database on Supabase (no BAA)
- Using OpenAI API (no BAA without Enterprise)

**Immediate Risk**: HIPAA violations with potential fines of $100-$50,000 per violation.

---

## Week 1: Critical Actions (START NOW)

### Day 1: Sign AWS BAA (2 hours)

**CRITICAL - DO THIS FIRST**

1. Log into AWS Console: https://console.aws.amazon.com/
2. Navigate to AWS Artifact:
   - Search for "Artifact" in the AWS Console
   - Or go to: https://console.aws.amazon.com/artifact/
3. Find "AWS Business Associate Addendum"
4. Click "Download and Accept"
5. Review the BAA
6. Accept the agreement
7. Download a copy for your records
8. **Screenshot the acceptance confirmation**

**You can now legally use AWS HIPAA-eligible services.**

### Day 1-2: Audit Current PHI (4 hours)

Create a spreadsheet documenting all PHI in your system:

| Data Type | Location | Count | Sensitivity |
|-----------|----------|-------|-------------|
| Patient Names | Supabase profiles table | ~XXX | High |
| Email Addresses | Supabase profiles table | ~XXX | Medium |
| Date of Birth | Supabase profiles table | ~XXX | High |
| VO2 Max Data | Supabase metabolic_tests | ~XXX | High |
| RMR Values | Supabase metabolic_tests | ~XXX | High |
| Generated Reports | Supabase reports table | ~XXX | High |

**Action**: Export this list and save it securely.

### Day 3: Designate Security Official (1 hour)

**HIPAA Requirement**: You must have a designated Security Official.

Create a document stating:
```
HIPAA Security Official Designation

Name: [Your Name or Team Member]
Title: [Title]
Date Appointed: [Date]
Responsibilities:
- Oversee HIPAA compliance
- Manage security incidents
- Coordinate audit responses
- Update policies and procedures
- Conduct staff training

Signature: ________________
Date: ________________
```

**Save this document** in a secure location.

### Day 4-5: Create AWS Account Structure (4 hours)

1. **Create AWS Account** (if you don't have one)
   - Go to: https://aws.amazon.com/
   - Click "Create an AWS Account"
   - Use a business email (not personal)
   - Enable MFA on root account immediately

2. **Set Up Billing Alerts**
   ```bash
   # In AWS Console → Billing → Budgets
   # Create budget for $500/month with alerts at:
   # - 50% threshold
   # - 80% threshold
   # - 100% threshold
   ```

3. **Create IAM Admin User**
   - Don't use root account for daily work
   - Create admin IAM user with MFA
   - Save credentials securely

### Day 5: Pause New PHI Processing (2 hours)

**CRITICAL**: Until your AWS infrastructure is ready:

1. Add banner to your website:
   ```html
   <div style="background: #ff6b6b; color: white; padding: 10px; text-align: center;">
     System Maintenance: Report generation temporarily unavailable while we upgrade to enhanced security. Expected completion: [Date 16 weeks from now]
   </div>
   ```

2. Disable new user registrations temporarily (optional but recommended)

3. Email existing users:
   ```
   Subject: Important: System Upgrade for Enhanced Security

   Dear MetaboMax Pro User,

   We're upgrading our infrastructure to provide enhanced security and
   HIPAA compliance for your health data. During this time (approximately
   4 months), report generation will be temporarily limited.

   Your existing data is safe and secure. We're making these changes to
   provide you with the highest level of data protection.

   Thank you for your patience.

   The MetaboMax Pro Team
   ```

---

## Week 2-4: AWS Infrastructure Setup

### Install Required Tools (1 hour)

```bash
# Install AWS CLI
# macOS
brew install awscli

# Verify installation
aws --version

# Configure AWS CLI
aws configure
# Enter:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region: us-east-1
# - Default output format: json

# Install Terraform
# macOS
brew install terraform

# Verify installation
terraform --version
```

### Set Up Terraform Backend (1 hour)

```bash
# Navigate to your project
cd /Users/markgentry/Sites/metabomaxpro.com/terraform

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

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### Create terraform.tfvars (30 minutes)

```bash
# In /Users/markgentry/Sites/metabomaxpro.com/terraform/

# Create terraform.tfvars
cat > terraform.tfvars << 'EOF'
aws_region  = "us-east-1"
account_id  = "YOUR_AWS_ACCOUNT_ID"  # Get from: aws sts get-caller-identity
environment = "production"

db_username = "metabomax_admin"
db_password = "CHANGE_THIS_TO_STRONG_RANDOM_PASSWORD"  # Use password generator
db_name     = "metabomaxpro"

domain_name = "metabomaxpro.com"

enable_multi_az             = true
enable_deletion_protection  = true
backup_retention_days       = 30
log_retention_days          = 365
EOF

# Add to .gitignore
echo "terraform.tfvars" >> .gitignore
echo "*.tfstate*" >> .gitignore
echo ".terraform/" >> .gitignore
```

### Deploy Core Infrastructure (2-4 hours)

```bash
# Initialize Terraform
cd /Users/markgentry/Sites/metabomaxpro.com/terraform
terraform init

# Validate configuration
terraform validate

# See what will be created
terraform plan

# Deploy (this will take 30-45 minutes)
terraform apply

# Type 'yes' when prompted
```

**What this creates:**
- VPC with public/private subnets
- RDS PostgreSQL database (encrypted)
- S3 buckets (encrypted)
- KMS encryption keys
- CloudTrail audit logging
- CloudWatch logging
- Security groups
- IAM roles

---

## Week 5-8: Database Migration

### Export Supabase Data (2 hours)

```bash
# Install Supabase CLI
npm install -g supabase

# Login to Supabase
supabase login

# Export schema
supabase db dump --schema-only > supabase_schema.sql

# Export data
supabase db dump --data-only > supabase_data.sql

# Or use pg_dump if you have connection string
pg_dump -h YOUR_SUPABASE_HOST -U postgres -d postgres \
  --schema-only > supabase_schema.sql

pg_dump -h YOUR_SUPABASE_HOST -U postgres -d postgres \
  --data-only > supabase_data.sql
```

### Import to AWS RDS (2 hours)

```bash
# Get RDS endpoint from Terraform output
terraform output rds_endpoint

# Import schema
psql -h YOUR_RDS_ENDPOINT -U metabomax_admin -d metabomaxpro \
  -f supabase_schema.sql

# Import data
psql -h YOUR_RDS_ENDPOINT -U metabomax_admin -d metabomaxpro \
  -f supabase_data.sql

# Verify data
psql -h YOUR_RDS_ENDPOINT -U metabomax_admin -d metabomaxpro \
  -c "SELECT COUNT(*) FROM profiles;"
```

### Update Application Code (4-8 hours)

Replace Supabase client with PostgreSQL:

```python
# OLD CODE (Supabase)
from supabase import create_client
supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# NEW CODE (RDS)
import psycopg2
from psycopg2 import pool

# Get credentials from Secrets Manager
import boto3
import json

def get_db_credentials():
    secrets_client = boto3.client('secretsmanager', region_name='us-east-1')
    response = secrets_client.get_secret_value(
        SecretId='metabomax/database/credentials'
    )
    return json.loads(response['SecretString'])

db_creds = get_db_credentials()
db_pool = psycopg2.pool.SimpleConnectionPool(
    minconn=1,
    maxconn=20,
    host=db_creds['host'],
    database=db_creds['database'],
    user=db_creds['username'],
    password=db_creds['password'],
    sslmode='require'
)
```

---

## Week 9-12: Security Enhancements

### Implement MFA (4 hours)

See detailed code in `HIPAA_COMPLIANCE_PLAN.md` Section 4.1

### Add Audit Logging (4 hours)

```python
# Create audit log table
CREATE TABLE phi_access_log (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    user_id UUID,
    action VARCHAR(50),
    table_name VARCHAR(100),
    ip_address INET,
    details JSONB
);

# Add logging to every PHI access
def log_phi_access(action, user_id, table, details):
    cursor.execute("""
        INSERT INTO phi_access_log (user_id, action, table_name, details)
        VALUES (%s, %s, %s, %s)
    """, (user_id, action, table, json.dumps(details)))
```

### Migrate to AWS Bedrock (4 hours)

```python
# OLD CODE (OpenAI)
from openai import OpenAI
client = OpenAI(api_key=OPENAI_API_KEY)

# NEW CODE (AWS Bedrock)
import boto3
import json

bedrock = boto3.client('bedrock-runtime', region_name='us-east-1')

def generate_recommendations(data):
    response = bedrock.invoke_model(
        modelId='anthropic.claude-3-sonnet-20240229-v1:0',
        body=json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 2000,
            "messages": [{
                "role": "user",
                "content": f"Generate recommendations for: {data}"
            }]
        })
    )
    return json.loads(response['body'].read())
```

---

## Week 13-14: Testing

### Security Testing Checklist

- [ ] Penetration testing of application
- [ ] SQL injection testing
- [ ] XSS vulnerability testing
- [ ] Authentication bypass testing
- [ ] Session management testing
- [ ] HTTPS/TLS validation
- [ ] Encryption verification
- [ ] Access control testing
- [ ] Audit log validation

### Compliance Testing Checklist

- [ ] Verify AWS BAA is signed
- [ ] All PHI encrypted at rest
- [ ] All PHI encrypted in transit
- [ ] Audit logging working
- [ ] Backups functioning
- [ ] MFA enabled for all users
- [ ] Session timeouts working
- [ ] Breach notification procedures documented

---

## Week 15-16: Deployment

### Pre-Deployment Checklist

- [ ] All tests passed
- [ ] Rollback plan created
- [ ] Team trained on new system
- [ ] Documentation complete
- [ ] Users notified of changes
- [ ] Monitoring dashboards set up

### Deployment Day

1. **Schedule maintenance window** (3-4 hours, low-traffic time)

2. **Final data sync** from Supabase to RDS
   ```bash
   # Export latest Supabase data
   pg_dump -h SUPABASE_HOST -U postgres -d postgres --data-only > final_data.sql

   # Import to RDS
   psql -h RDS_ENDPOINT -U metabomax_admin -d metabomaxpro -f final_data.sql
   ```

3. **Update DNS** to point to AWS ALB
   ```bash
   # In your DNS provider (e.g., Route 53)
   # Change A record for metabomaxpro.com to ALB DNS name
   ```

4. **Deploy application** to ECS
   ```bash
   # Build and push Docker image
   docker build -t metabomax-app .
   docker tag metabomax-app:latest YOUR_ECR_REPO:latest
   docker push YOUR_ECR_REPO:latest

   # Update ECS service
   aws ecs update-service \
     --cluster metabomax-hipaa-cluster \
     --service metabomax-service \
     --force-new-deployment
   ```

5. **Verify everything works**
   - Test login
   - Test report generation
   - Verify audit logs
   - Check monitoring dashboards

6. **Make Supabase read-only** (keep as backup for 30 days)

7. **Announce completion** to users

---

## Post-Deployment: First 30 Days

### Daily Tasks
- [ ] Review audit logs for suspicious activity
- [ ] Check CloudWatch dashboards for errors
- [ ] Monitor backup success
- [ ] Review access patterns

### Weekly Tasks
- [ ] Security incident review
- [ ] Performance optimization
- [ ] User feedback review
- [ ] Cost analysis

### Month 1 Completion
- [ ] Conduct internal compliance audit
- [ ] Document lessons learned
- [ ] Update procedures based on experience
- [ ] Schedule external compliance audit

---

## Emergency Contacts and Resources

### AWS Support
- Console: https://console.aws.amazon.com/support/
- Phone: 1-866-987-2577 (US)
- Documentation: https://aws.amazon.com/compliance/hipaa-compliance/

### HIPAA Resources
- HHS HIPAA Site: https://www.hhs.gov/hipaa/
- Breach Portal: https://ocrportal.hhs.gov/ocr/breach/breach_report.jsf
- HIPAA Hotline: 1-800-368-1019

### Security Incident Response
1. **Identify**: Detect the incident
2. **Contain**: Isolate affected systems
3. **Investigate**: Determine scope
4. **Remediate**: Fix the issue
5. **Document**: Record everything
6. **Notify**: If breach affects >1 user, notify within 60 days

---

## Success Metrics

After implementation, you should be able to say:

- [ ] "We have a signed BAA with AWS"
- [ ] "All PHI is encrypted at rest and in transit"
- [ ] "We log every access to PHI"
- [ ] "We have MFA enabled for all users"
- [ ] "We conduct daily security reviews"
- [ ] "We have a tested disaster recovery plan"
- [ ] "We train staff on HIPAA annually"
- [ ] "We conduct annual compliance audits"

---

## Common Pitfalls to Avoid

1. **Don't skip the BAA** - This is the most critical step
2. **Don't use services without BAA** - Ensure every vendor has a BAA if they touch PHI
3. **Don't forget audit logging** - You need to log every PHI access
4. **Don't skip encryption** - Both at rest and in transit
5. **Don't ignore backups** - Test your disaster recovery plan
6. **Don't delay training** - Everyone who touches PHI needs training
7. **Don't forget documentation** - HIPAA is documentation-heavy
8. **Don't ignore incidents** - Have a documented response plan

---

## Cost Summary

### One-Time Costs
- AWS infrastructure setup: $5,000-10,000 (developer time)
- Security consulting: $2,000-5,000
- Testing and audit: $1,000-3,000
- **Total**: $8,000-18,000

### Monthly Costs
- AWS infrastructure: ~$291/month
- AWS Bedrock (Claude): ~$100-300/month
- **Total**: ~$400-600/month

### ROI
- **Risk avoided**: $250,000-1,500,000+ in potential fines
- **Business value**: Ability to operate legally with PHI
- **Market advantage**: HIPAA-compliant status for marketing

---

## Questions?

Refer to:
- **HIPAA_COMPLIANCE_PLAN.md** (80+ pages) - Complete technical implementation
- **HIPAA_EXECUTIVE_SUMMARY.md** - High-level overview for stakeholders
- **terraform/README.md** - Infrastructure deployment guide

---

**Good luck with your HIPAA compliance journey!**

Remember: This is not optional. Processing PHI without HIPAA compliance is illegal and puts your business and users at serious risk.

Start with Week 1 actions TODAY.
