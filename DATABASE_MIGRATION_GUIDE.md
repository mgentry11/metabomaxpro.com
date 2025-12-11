# Supabase to AWS RDS Migration Guide for HIPAA Compliance

## Executive Summary

**Current Database**: Supabase PostgreSQL (NOT HIPAA compliant)
**Target Database**: AWS RDS PostgreSQL (HIPAA compliant with BAA)
**Migration Duration**: 3-4 weeks
**Downtime Required**: 2-4 hours for final cutover

## Why Migration is Required

### Supabase HIPAA Limitations

| Requirement | Supabase Hosted | AWS RDS |
|-------------|----------------|---------|
| **BAA Available** | NO | YES |
| **HIPAA Compliant** | NO (unless self-hosted) | YES |
| **Audit Logging** | Basic | Comprehensive (CloudTrail) |
| **Encryption at Rest** | Yes | Yes (with KMS) |
| **Encryption in Transit** | Yes | Yes |
| **Multi-AZ** | No | Yes |
| **Point-in-Time Recovery** | Limited | Full (35 days) |
| **Automated Backups** | Yes | Yes (configurable) |
| **Access Controls** | Basic | Advanced (IAM + VPC) |

**Critical Issue**: Supabase does not offer a Business Associate Agreement (BAA) for their hosted service, making it **illegal to store PHI** on their platform under HIPAA.

## Current Database Schema

### Tables in Supabase

Based on the CLAUDE.md documentation, your current schema includes:

```sql
-- profiles table (extends Supabase auth.users)
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id),
    email TEXT UNIQUE NOT NULL,
    full_name TEXT,
    date_of_birth DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- metabolic_tests table
CREATE TABLE metabolic_tests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES profiles(id),
    test_date DATE NOT NULL,
    vo2_max DECIMAL(5,2),
    rmr INTEGER,
    rer DECIMAL(3,2),
    heart_rate_zones JSONB,
    raw_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- reports table
CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES profiles(id),
    test_id UUID REFERENCES metabolic_tests(id),
    report_type VARCHAR(50), -- 'basic', 'premium', 'super_premium'
    pdf_url TEXT,
    html_content TEXT,
    biological_age INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- subscriptions table
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES profiles(id),
    tier VARCHAR(50), -- 'free', 'unlimited_basic', 'ai_enhanced', 'pro'
    status VARCHAR(50), -- 'active', 'cancelled', 'expired'
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    reports_remaining INTEGER,
    ai_credits_remaining INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### Identifying PHI in Database

**PHI (Protected Health Information) includes:**

| Table | Column | PHI Type |
|-------|--------|----------|
| profiles | email | Identifier |
| profiles | full_name | Identifier |
| profiles | date_of_birth | Demographic |
| metabolic_tests | vo2_max | Health data |
| metabolic_tests | rmr | Health data |
| metabolic_tests | rer | Health data |
| metabolic_tests | heart_rate_zones | Health data |
| reports | biological_age | Health data |
| reports | html_content | Health data |

**Total PHI Data**: Essentially all user data except payment/subscription metadata.

## Migration Strategy

### Option 1: Full Migration (Recommended)

**Approach**: Migrate entire database from Supabase to AWS RDS in one operation.

**Pros**:
- Single migration event
- Faster overall timeline
- Simpler to manage
- Clean cutover

**Cons**:
- Requires maintenance window (2-4 hours)
- All-or-nothing approach
- More disruptive to users

**Timeline**: 3 weeks

### Option 2: Gradual Migration

**Approach**: Migrate tables incrementally, running dual databases temporarily.

**Pros**:
- Lower risk per step
- Can test incrementally
- Minimal downtime

**Cons**:
- Complex data synchronization
- Longer overall timeline
- Higher development effort
- Data consistency challenges

**Timeline**: 6-8 weeks

**Recommendation**: Option 1 (Full Migration)

## Pre-Migration Checklist

### Week 1: Planning and Preparation

#### Day 1-2: Document Current State

```bash
# Export current schema
supabase db dump --schema-only > current_schema.sql

# Document all tables
psql -h SUPABASE_HOST -U postgres -d postgres -c "\dt"

# Count records in each table
psql -h SUPABASE_HOST -U postgres -d postgres << EOF
SELECT 'profiles' as table_name, COUNT(*) as count FROM profiles
UNION ALL
SELECT 'metabolic_tests', COUNT(*) FROM metabolic_tests
UNION ALL
SELECT 'reports', COUNT(*) FROM reports
UNION ALL
SELECT 'subscriptions', COUNT(*) FROM subscriptions;
EOF
```

**Document:**
- Number of users: ______
- Number of metabolic tests: ______
- Number of reports: ______
- Number of subscriptions: ______
- Total database size: ______ MB
- Largest table: ______

#### Day 3-4: Set Up AWS RDS

Use Terraform to deploy RDS:

```bash
cd /Users/markgentry/Sites/metabomaxpro.com/terraform

# Deploy RDS module
terraform apply -target=aws_db_instance.metabomax_primary

# Get RDS endpoint
terraform output rds_endpoint
```

**RDS Configuration (from Terraform)**:
- Instance: db.t3.medium
- Storage: 100GB (SSD)
- Multi-AZ: Enabled
- Encryption: KMS
- Backups: 30 days retention
- Monitoring: CloudWatch enabled

#### Day 5: Test Connectivity

```bash
# Install PostgreSQL client
brew install postgresql

# Test connection to RDS
psql -h YOUR_RDS_ENDPOINT \
     -U metabomax_admin \
     -d metabomaxpro \
     -c "SELECT version();"

# Should see PostgreSQL version
```

### Week 2: Schema Migration

#### Step 1: Export Supabase Schema

```bash
# Export schema only (no data yet)
pg_dump -h SUPABASE_HOST \
        -U postgres \
        -d postgres \
        --schema-only \
        --no-owner \
        --no-privileges \
        > supabase_schema.sql

# Review the schema
cat supabase_schema.sql
```

#### Step 2: Modify Schema for RDS

Create `rds_schema.sql` with modifications:

```sql
-- RDS-specific schema modifications

-- Drop Supabase-specific extensions we don't need
-- DROP EXTENSION IF EXISTS supabase_functions;

-- Create necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Profiles table (without Supabase auth dependency)
CREATE TABLE profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL, -- Store hashed passwords
    full_name TEXT,
    date_of_birth_encrypted BYTEA, -- Encrypted field
    mfa_secret TEXT, -- For multi-factor auth
    mfa_enabled BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_login TIMESTAMP WITH TIME ZONE
);

-- Create index on email for fast lookups
CREATE INDEX idx_profiles_email ON profiles(email);

-- Metabolic tests table (unchanged)
CREATE TABLE metabolic_tests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    test_date DATE NOT NULL,
    vo2_max DECIMAL(5,2),
    rmr INTEGER,
    rer DECIMAL(3,2),
    heart_rate_zones JSONB,
    raw_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_metabolic_tests_user_id ON metabolic_tests(user_id);
CREATE INDEX idx_metabolic_tests_test_date ON metabolic_tests(test_date);

-- Reports table (unchanged)
CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    test_id UUID REFERENCES metabolic_tests(id) ON DELETE SET NULL,
    report_type VARCHAR(50),
    pdf_s3_key TEXT, -- S3 key instead of URL
    html_content TEXT,
    biological_age INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_reports_user_id ON reports(user_id);
CREATE INDEX idx_reports_created_at ON reports(created_at);

-- Subscriptions table (unchanged)
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    tier VARCHAR(50),
    status VARCHAR(50),
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    reports_remaining INTEGER,
    ai_credits_remaining INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_subscriptions_user_id ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_stripe_customer_id ON subscriptions(stripe_customer_id);

-- HIPAA Audit Log Table (NEW)
CREATE TABLE phi_access_log (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    user_id UUID,
    action VARCHAR(50) NOT NULL, -- READ, WRITE, UPDATE, DELETE
    table_name VARCHAR(100),
    record_id VARCHAR(100),
    ip_address INET,
    user_agent TEXT,
    details JSONB,
    success BOOLEAN DEFAULT true
);

CREATE INDEX idx_phi_access_log_user_id ON phi_access_log(user_id);
CREATE INDEX idx_phi_access_log_timestamp ON phi_access_log(timestamp);
CREATE INDEX idx_phi_access_log_action ON phi_access_log(action);

-- Enable Row Level Security on audit log
ALTER TABLE phi_access_log ENABLE ROW LEVEL SECURITY;

-- Audit log is append-only
CREATE POLICY phi_access_log_append_only ON phi_access_log
    FOR INSERT
    WITH CHECK (true);

CREATE POLICY phi_access_log_no_delete ON phi_access_log
    FOR DELETE
    USING (false);

CREATE POLICY phi_access_log_no_update ON phi_access_log
    FOR UPDATE
    USING (false);

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_subscriptions_updated_at
    BEFORE UPDATE ON subscriptions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
```

#### Step 3: Import Schema to RDS

```bash
# Import the modified schema
psql -h YOUR_RDS_ENDPOINT \
     -U metabomax_admin \
     -d metabomaxpro \
     -f rds_schema.sql

# Verify tables created
psql -h YOUR_RDS_ENDPOINT \
     -U metabomax_admin \
     -d metabomaxpro \
     -c "\dt"
```

### Week 3: Data Migration

#### Step 1: Export Data from Supabase

```bash
# Export all data (CSV format for inspection)
psql -h SUPABASE_HOST -U postgres -d postgres -c "\copy profiles TO 'profiles.csv' CSV HEADER"
psql -h SUPABASE_HOST -U postgres -d postgres -c "\copy metabolic_tests TO 'metabolic_tests.csv' CSV HEADER"
psql -h SUPABASE_HOST -U postgres -d postgres -c "\copy reports TO 'reports.csv' CSV HEADER"
psql -h SUPABASE_HOST -U postgres -d postgres -c "\copy subscriptions TO 'subscriptions.csv' CSV HEADER"

# Or export as SQL INSERT statements
pg_dump -h SUPABASE_HOST \
        -U postgres \
        -d postgres \
        --data-only \
        --no-owner \
        --no-privileges \
        --table=profiles \
        --table=metabolic_tests \
        --table=reports \
        --table=subscriptions \
        > supabase_data.sql
```

#### Step 2: Transform Data for RDS

Create `transform_data.py`:

```python
#!/usr/bin/env python3
"""
Transform Supabase data for AWS RDS import
"""

import csv
import psycopg2
from psycopg2.extras import execute_batch
import os
from cryptography.fernet import Fernet
import base64

# RDS connection
rds_conn = psycopg2.connect(
    host=os.environ['RDS_ENDPOINT'],
    database='metabomaxpro',
    user='metabomax_admin',
    password=os.environ['DB_PASSWORD'],
    sslmode='require'
)

# Encryption key (from AWS Secrets Manager)
ENCRYPTION_KEY = os.environ['ENCRYPTION_KEY'].encode()
cipher = Fernet(ENCRYPTION_KEY)

def encrypt_field(value):
    """Encrypt sensitive field"""
    if value is None:
        return None
    encrypted = cipher.encrypt(value.encode())
    return base64.b64encode(encrypted).decode()

def import_profiles():
    """Import profiles with encryption"""
    cursor = rds_conn.cursor()

    with open('profiles.csv', 'r') as f:
        reader = csv.DictReader(f)
        rows = []

        for row in reader:
            # Encrypt date of birth
            dob_encrypted = None
            if row['date_of_birth']:
                dob_encrypted = encrypt_field(row['date_of_birth'])

            rows.append((
                row['id'],
                row['email'],
                row.get('password_hash', ''),  # May need to migrate from Supabase auth
                row.get('full_name'),
                dob_encrypted,
                False,  # mfa_enabled
                row['created_at'],
                row.get('updated_at', row['created_at'])
            ))

        # Batch insert
        execute_batch(cursor, """
            INSERT INTO profiles
            (id, email, password_hash, full_name, date_of_birth_encrypted,
             mfa_enabled, created_at, updated_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (id) DO NOTHING
        """, rows)

    rds_conn.commit()
    cursor.close()
    print(f"Imported {len(rows)} profiles")

def import_metabolic_tests():
    """Import metabolic tests"""
    cursor = rds_conn.cursor()

    with open('metabolic_tests.csv', 'r') as f:
        reader = csv.DictReader(f)
        rows = [(
            row['id'],
            row['user_id'],
            row['test_date'],
            row.get('vo2_max'),
            row.get('rmr'),
            row.get('rer'),
            row.get('heart_rate_zones'),
            row.get('raw_data'),
            row['created_at']
        ) for row in reader]

        execute_batch(cursor, """
            INSERT INTO metabolic_tests
            (id, user_id, test_date, vo2_max, rmr, rer,
             heart_rate_zones, raw_data, created_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (id) DO NOTHING
        """, rows)

    rds_conn.commit()
    cursor.close()
    print(f"Imported {len(rows)} metabolic tests")

def import_reports():
    """Import reports"""
    cursor = rds_conn.cursor()

    with open('reports.csv', 'r') as f:
        reader = csv.DictReader(f)
        rows = [(
            row['id'],
            row['user_id'],
            row.get('test_id'),
            row.get('report_type'),
            row.get('pdf_url'),  # Will need to migrate to S3
            row.get('html_content'),
            row.get('biological_age'),
            row['created_at']
        ) for row in reader]

        execute_batch(cursor, """
            INSERT INTO reports
            (id, user_id, test_id, report_type, pdf_s3_key,
             html_content, biological_age, created_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (id) DO NOTHING
        """, rows)

    rds_conn.commit()
    cursor.close()
    print(f"Imported {len(rows)} reports")

def import_subscriptions():
    """Import subscriptions"""
    cursor = rds_conn.cursor()

    with open('subscriptions.csv', 'r') as f:
        reader = csv.DictReader(f)
        rows = [(
            row['id'],
            row['user_id'],
            row.get('tier'),
            row.get('status'),
            row.get('stripe_customer_id'),
            row.get('stripe_subscription_id'),
            row.get('reports_remaining'),
            row.get('ai_credits_remaining'),
            row['created_at'],
            row.get('updated_at', row['created_at'])
        ) for row in reader]

        execute_batch(cursor, """
            INSERT INTO subscriptions
            (id, user_id, tier, status, stripe_customer_id,
             stripe_subscription_id, reports_remaining,
             ai_credits_remaining, created_at, updated_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (id) DO NOTHING
        """, rows)

    rds_conn.commit()
    cursor.close()
    print(f"Imported {len(rows)} subscriptions")

def verify_data():
    """Verify data integrity after import"""
    cursor = rds_conn.cursor()

    tables = ['profiles', 'metabolic_tests', 'reports', 'subscriptions']
    for table in tables:
        cursor.execute(f"SELECT COUNT(*) FROM {table}")
        count = cursor.fetchone()[0]
        print(f"{table}: {count} rows")

    cursor.close()

if __name__ == '__main__':
    print("Starting data import...")
    import_profiles()
    import_metabolic_tests()
    import_reports()
    import_subscriptions()
    verify_data()
    print("Data import complete!")
    rds_conn.close()
```

#### Step 3: Run Data Import

```bash
# Set environment variables
export RDS_ENDPOINT="your-rds-endpoint.rds.amazonaws.com"
export DB_PASSWORD="your-db-password"
export ENCRYPTION_KEY="your-encryption-key"

# Run import script
python3 transform_data.py

# Verify counts match
# Compare Supabase counts vs RDS counts
```

#### Step 4: Data Validation

```python
#!/usr/bin/env python3
"""
Validate data migration integrity
"""

import psycopg2
import sys

# Connect to both databases
supabase_conn = psycopg2.connect(
    host=SUPABASE_HOST,
    database='postgres',
    user='postgres',
    password=SUPABASE_PASSWORD
)

rds_conn = psycopg2.connect(
    host=RDS_ENDPOINT,
    database='metabomaxpro',
    user='metabomax_admin',
    password=RDS_PASSWORD
)

def compare_counts():
    """Compare record counts"""
    tables = ['profiles', 'metabolic_tests', 'reports', 'subscriptions']

    for table in tables:
        # Supabase count
        sb_cursor = supabase_conn.cursor()
        sb_cursor.execute(f"SELECT COUNT(*) FROM {table}")
        sb_count = sb_cursor.fetchone()[0]
        sb_cursor.close()

        # RDS count
        rds_cursor = rds_conn.cursor()
        rds_cursor.execute(f"SELECT COUNT(*) FROM {table}")
        rds_count = rds_cursor.fetchone()[0]
        rds_cursor.close()

        status = "✓" if sb_count == rds_count else "✗"
        print(f"{status} {table}: Supabase={sb_count}, RDS={rds_count}")

        if sb_count != rds_count:
            print(f"  ERROR: Count mismatch for {table}")
            return False

    return True

def sample_check():
    """Check a sample of records match"""
    sb_cursor = supabase_conn.cursor()
    rds_cursor = rds_conn.cursor()

    # Get 10 random user IDs from Supabase
    sb_cursor.execute("SELECT id FROM profiles ORDER BY RANDOM() LIMIT 10")
    user_ids = [row[0] for row in sb_cursor.fetchall()]

    for user_id in user_ids:
        # Check profile exists in RDS
        rds_cursor.execute("SELECT email FROM profiles WHERE id = %s", (user_id,))
        result = rds_cursor.fetchone()

        if not result:
            print(f"✗ User {user_id} missing in RDS")
            return False

    print("✓ Sample check passed (10 random users verified)")

    sb_cursor.close()
    rds_cursor.close()
    return True

if __name__ == '__main__':
    print("Validating data migration...")

    if not compare_counts():
        print("FAILED: Count mismatch")
        sys.exit(1)

    if not sample_check():
        print("FAILED: Sample check failed")
        sys.exit(1)

    print("✓ All validation checks passed!")
    sys.exit(0)
```

### Week 4: Application Migration and Testing

#### Step 1: Update Application Code

Replace Supabase client code with PostgreSQL:

```python
# app.py - OLD CODE
from supabase import create_client

supabase_url = os.environ.get('SUPABASE_URL')
supabase_key = os.environ.get('SUPABASE_KEY')
supabase = create_client(supabase_url, supabase_key)

# Query example (OLD)
response = supabase.table('profiles').select('*').eq('id', user_id).execute()
profile = response.data[0] if response.data else None
```

```python
# app.py - NEW CODE
import psycopg2
from psycopg2 import pool
import boto3
import json

# Get database credentials from Secrets Manager
def get_db_credentials():
    secrets_client = boto3.client('secretsmanager', region_name='us-east-1')
    response = secrets_client.get_secret_value(
        SecretId='metabomax/database/credentials'
    )
    return json.loads(response['SecretString'])

# Initialize connection pool
db_creds = get_db_credentials()
db_pool = psycopg2.pool.ThreadedConnectionPool(
    minconn=1,
    maxconn=20,
    host=db_creds['host'],
    port=db_creds['port'],
    database=db_creds['database'],
    user=db_creds['username'],
    password=db_creds['password'],
    sslmode='require',
    connect_timeout=10
)

def get_db_connection():
    return db_pool.getconn()

def release_db_connection(conn):
    db_pool.putconn(conn)

# Query example (NEW)
conn = get_db_connection()
cursor = conn.cursor()

try:
    cursor.execute("SELECT * FROM profiles WHERE id = %s", (user_id,))
    profile = cursor.fetchone()
finally:
    cursor.close()
    release_db_connection(conn)
```

#### Step 2: Testing

Create comprehensive test suite:

```python
# tests/test_database.py
import pytest
import psycopg2

def test_connection():
    """Test RDS connection"""
    conn = get_db_connection()
    assert conn is not None
    cursor = conn.cursor()
    cursor.execute("SELECT 1")
    result = cursor.fetchone()
    assert result[0] == 1
    cursor.close()
    release_db_connection(conn)

def test_user_query():
    """Test querying user profile"""
    # Create test user
    conn = get_db_connection()
    cursor = conn.cursor()

    test_email = f"test_{uuid.uuid4()}@example.com"
    cursor.execute("""
        INSERT INTO profiles (email, password_hash, full_name)
        VALUES (%s, %s, %s)
        RETURNING id
    """, (test_email, 'test_hash', 'Test User'))

    user_id = cursor.fetchone()[0]
    conn.commit()

    # Query user
    cursor.execute("SELECT email FROM profiles WHERE id = %s", (user_id,))
    result = cursor.fetchone()

    assert result[0] == test_email

    # Cleanup
    cursor.execute("DELETE FROM profiles WHERE id = %s", (user_id,))
    conn.commit()

    cursor.close()
    release_db_connection(conn)

def test_audit_logging():
    """Test PHI access logging"""
    conn = get_db_connection()
    cursor = conn.cursor()

    # Insert audit log entry
    cursor.execute("""
        INSERT INTO phi_access_log (user_id, action, table_name, details)
        VALUES (%s, %s, %s, %s)
    """, (
        str(uuid.uuid4()),
        'READ',
        'profiles',
        json.dumps({'test': True})
    ))

    conn.commit()

    # Verify insert
    cursor.execute("SELECT COUNT(*) FROM phi_access_log WHERE action = 'READ'")
    count = cursor.fetchone()[0]

    assert count > 0

    cursor.close()
    release_db_connection(conn)

# Run tests
pytest tests/test_database.py -v
```

## Cutover Plan

### Final Migration Day (Schedule 4-hour maintenance window)

#### T-4 hours: Preparation

```bash
# 1. Announce maintenance window to users
# 2. Stop all background jobs
# 3. Set application to read-only mode
# 4. Take final Supabase backup

pg_dump -h SUPABASE_HOST -U postgres -d postgres \
  --format=custom \
  --file=final_backup_$(date +%Y%m%d_%H%M%S).dump
```

#### T-2 hours: Final Data Sync

```bash
# Export only records created/updated since last sync
pg_dump -h SUPABASE_HOST -U postgres -d postgres \
  --data-only \
  --table=profiles \
  --table=metabolic_tests \
  --table=reports \
  --table=subscriptions \
  > final_delta.sql

# Import to RDS
psql -h RDS_ENDPOINT -U metabomax_admin -d metabomaxpro \
  -f final_delta.sql
```

#### T-1 hour: Validation

```bash
# Run validation script
python3 validate_migration.py

# Verify counts match exactly
# Test application against RDS
```

#### T-0: Cutover

```bash
# 1. Update application environment variables
export DATABASE_HOST=$RDS_ENDPOINT
export DATABASE_NAME=metabomaxpro
export DATABASE_USER=metabomax_admin

# 2. Restart application
# If using ECS:
aws ecs update-service \
  --cluster metabomax-cluster \
  --service metabomax-service \
  --force-new-deployment

# 3. Monitor for errors
# Check CloudWatch logs
# Test key workflows:
# - User login
# - Report generation
# - Data retrieval
```

#### T+1 hour: Verification

```bash
# Test all major features:
# - User registration ✓
# - User login ✓
# - Upload test results ✓
# - Generate report ✓
# - View report history ✓
# - Update profile ✓

# Check audit logs
psql -h RDS_ENDPOINT -U metabomax_admin -d metabomaxpro \
  -c "SELECT COUNT(*) FROM phi_access_log WHERE timestamp > NOW() - INTERVAL '1 hour'"
```

#### T+2 hours: Make Supabase Read-Only

```sql
-- In Supabase dashboard, revoke write permissions
-- Keep as backup for 30 days, then delete
```

## Rollback Plan

If issues arise during cutover:

```bash
# 1. Immediately revert to Supabase
export DATABASE_HOST=$SUPABASE_HOST
export DATABASE_NAME=postgres

# 2. Restart application
aws ecs update-service \
  --cluster metabomax-cluster \
  --service metabomax-service \
  --force-new-deployment

# 3. Announce rollback to users
# 4. Investigate issues
# 5. Fix problems
# 6. Reschedule cutover
```

## Post-Migration Tasks

### Week 1 After Migration

- [ ] Monitor RDS performance daily
- [ ] Check CloudWatch metrics
- [ ] Review audit logs
- [ ] Verify backups are running
- [ ] Test disaster recovery
- [ ] Monitor application errors
- [ ] Gather user feedback

### Week 2-4 After Migration

- [ ] Optimize database queries
- [ ] Tune RDS parameters
- [ ] Review security groups
- [ ] Conduct security audit
- [ ] Update documentation
- [ ] Train team on new system

### 30 Days After Migration

- [ ] Delete Supabase database (after verification everything works)
- [ ] Cancel Supabase subscription
- [ ] Update disaster recovery procedures
- [ ] Conduct lessons learned review

## Cost Comparison

### Supabase (Before)
- Pro Plan: $25/month
- Additional users: ~$25-50/month
- **Total**: ~$50-75/month

### AWS RDS (After)
- db.t3.medium Multi-AZ: ~$120/month
- Storage (100GB): ~$10/month
- Backup storage: ~$5/month
- Data transfer: ~$5/month
- **Total**: ~$140/month

**Additional Cost**: ~$65-90/month

**Value Gained**:
- HIPAA compliance (required by law)
- Better security (encryption, audit logs)
- Better availability (Multi-AZ)
- Better backups (35-day point-in-time recovery)
- Lower legal risk (BAA protection)

## Troubleshooting

### Issue: Connection Timeout

```bash
# Check security group
aws ec2 describe-security-groups \
  --group-ids sg-xxxxx

# Verify VPC routing
# Ensure private subnets can reach RDS
```

### Issue: Authentication Failed

```bash
# Verify credentials in Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id metabomax/database/credentials

# Test connection manually
psql -h RDS_ENDPOINT -U metabomax_admin -d metabomaxpro
```

### Issue: Slow Queries

```sql
-- Enable query logging
ALTER DATABASE metabomaxpro SET log_statement = 'all';

-- Find slow queries
SELECT * FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10;

-- Add missing indexes
CREATE INDEX idx_reports_user_created
ON reports(user_id, created_at DESC);
```

## Support Resources

- AWS RDS Documentation: https://docs.aws.amazon.com/rds/
- PostgreSQL Documentation: https://www.postgresql.org/docs/
- Migration best practices: https://aws.amazon.com/blogs/database/

## Summary Checklist

- [ ] Document current Supabase schema and data
- [ ] Set up AWS RDS with HIPAA configuration
- [ ] Export schema from Supabase
- [ ] Modify schema for RDS (add audit logging, encryption)
- [ ] Import schema to RDS
- [ ] Export data from Supabase
- [ ] Transform data (encrypt sensitive fields)
- [ ] Import data to RDS
- [ ] Validate data integrity
- [ ] Update application code
- [ ] Test thoroughly
- [ ] Schedule maintenance window
- [ ] Perform final data sync
- [ ] Cut over to RDS
- [ ] Verify everything works
- [ ] Monitor for 30 days
- [ ] Delete Supabase database

**Estimated Total Time**: 3-4 weeks of development + 4-hour cutover window

Good luck with your migration! This is a critical step toward HIPAA compliance.
