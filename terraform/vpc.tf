# VPC Configuration for MetaboMax Pro HIPAA Infrastructure

# VPC
resource "aws_vpc" "metabomax_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "metabomax-vpc-${var.environment}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.metabomax_vpc.id

  tags = {
    Name = "metabomax-igw-${var.environment}"
  }
}

# Public Subnets (for ALB and NAT Gateway)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.metabomax_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "metabomax-public-subnet-${count.index + 1}-${var.environment}"
    Type = "Public"
  }
}

# Private Subnets for Application (ECS Tasks)
resource "aws_subnet" "private_app" {
  count             = 2
  vpc_id            = aws_vpc.metabomax_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "metabomax-private-app-subnet-${count.index + 1}-${var.environment}"
    Type = "Private-App"
  }
}

# Private Subnets for Database (RDS)
resource "aws_subnet" "private_db" {
  count             = 2
  vpc_id            = aws_vpc.metabomax_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 20)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "metabomax-private-db-subnet-${count.index + 1}-${var.environment}"
    Type = "Private-Database"
  }
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count  = 2
  domain = "vpc"

  tags = {
    Name = "metabomax-nat-eip-${count.index + 1}-${var.environment}"
  }

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateways (one per AZ for high availability)
resource "aws_nat_gateway" "main" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "metabomax-nat-gw-${count.index + 1}-${var.environment}"
  }

  depends_on = [aws_internet_gateway.main]
}

# Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.metabomax_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "metabomax-public-rt-${var.environment}"
  }
}

# Route Table Associations for Public Subnets
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route Tables for Private App Subnets
resource "aws_route_table" "private_app" {
  count  = 2
  vpc_id = aws_vpc.metabomax_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "metabomax-private-app-rt-${count.index + 1}-${var.environment}"
  }
}

# Route Table Associations for Private App Subnets
resource "aws_route_table_association" "private_app" {
  count          = 2
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

# Route Tables for Private DB Subnets (no internet access)
resource "aws_route_table" "private_db" {
  count  = 2
  vpc_id = aws_vpc.metabomax_vpc.id

  tags = {
    Name = "metabomax-private-db-rt-${count.index + 1}-${var.environment}"
  }
}

# Route Table Associations for Private DB Subnets
resource "aws_route_table_association" "private_db" {
  count          = 2
  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db[count.index].id
}

# VPC Flow Logs (HIPAA Requirement)
resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.vpc_flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.metabomax_vpc.id

  tags = {
    Name = "metabomax-vpc-flow-log-${var.environment}"
  }
}

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name              = "/aws/vpc/metabomax-${var.environment}"
  retention_in_days = 2557 # 7 years for HIPAA compliance
  kms_key_id        = aws_kms_key.cloudwatch.arn

  tags = {
    Name = "metabomax-vpc-flow-log-${var.environment}"
  }
}

resource "aws_iam_role" "vpc_flow_log" {
  name = "metabomax-vpc-flow-log-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "vpc_flow_log" {
  name = "metabomax-vpc-flow-log-policy-${var.environment}"
  role = aws_iam_role.vpc_flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}
