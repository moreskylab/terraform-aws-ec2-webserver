Looking at your AWS Terraform configuration, I can see it's already well-structured. However, I notice there are a few improvements that can be made and the `random_id` resource should be defined before it's used. Here's an optimized version of your AWS configuration:

````hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# Generate a random suffix for global uniqueness (moved to top)
resource "random_id" "suffix" {
  byte_length = 4
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "tf-main-vpc"
  }
}

# Create a public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-south-1a"

  tags = {
    Name = "tf-public-subnet"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "tf-main-igw"
  }
}

# Create a route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "tf-public-rt"
  }
}

# Associate route table with subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Create a security group
resource "aws_security_group" "web" {
  name        = "tf-web-sg"
  description = "Allow web traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # In production, restrict this to your IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tf-web-sg"
  }
}

# Create an S3 bucket for logs
resource "aws_s3_bucket" "logs" {
  bucket = "tf-web-server-logs-${random_id.suffix.hex}"

  tags = {
    Name = "tf-web-server-logs"
  }
}

# Configure S3 bucket versioning
resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access to the bucket
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create the IAM Policy Document
data "aws_iam_policy_document" "ec2_s3_upload_policy" {
  statement {
    sid = "AllowEC2ToUploadLogs"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]
    resources = [
      "${aws_s3_bucket.logs.arn}/*"
    ]
  }

  statement {
    sid = "AllowEC2ToListBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      aws_s3_bucket.logs.arn
    ]
  }
}

# Create the IAM Policy
resource "aws_iam_policy" "ec2_s3_upload_policy" {
  name        = "EC2S3UploadLogsPolicy"
  description = "Policy to allow EC2 instance to upload logs to S3"
  policy      = data.aws_iam_policy_document.ec2_s3_upload_policy.json

  tags = {
    Name = "EC2S3UploadLogsPolicy"
  }
}

# Create an IAM Role
resource "aws_iam_role" "ec2_s3_uploader_role" {
  name = "EC2S3UploaderRole"
  description = "Role for EC2 instance to upload logs to S3"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "EC2S3UploaderRole"
  }
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "ec2_s3_upload_attachment" {
  role       = aws_iam_role.ec2_s3_uploader_role.name
  policy_arn = aws_iam_policy.ec2_s3_upload_policy.arn
}

# Create an IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_s3_uploader_profile" {
  name = "EC2S3UploaderProfile"
  role = aws_iam_role.ec2_s3_uploader_role.name

  tags = {
    Name = "EC2S3UploaderProfile"
  }
}

# Data source to get the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Create an EC2 instance
resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"  # Updated to t3.micro for better performance
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = "ap-south-1"  # Make sure this key pair exists
  iam_instance_profile   = aws_iam_instance_profile.ec2_s3_uploader_profile.name

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    bucket_name = aws_s3_bucket.logs.bucket
  }))

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  tags = {
    Name = "tf-web-server"
  }
}

# Output the web server's public IP
output "web_server_public_ip" {
  description = "Public IP address of the web server"
  value       = aws_instance.web.public_ip
}

# Output the web server's public DNS
output "web_server_public_dns" {
  description = "Public DNS name of the web server"
  value       = aws_instance.web.public_dns
}

# Output the S3 bucket name
output "logs_bucket" {
  description = "Name of the S3 bucket for logs"
  value       = aws_s3_bucket.logs.bucket
}

# Output the S3 bucket ARN
output "logs_bucket_arn" {
  description = "ARN of the S3 bucket for logs"
  value       = aws_s3_bucket.logs.arn
}
````

Now create a separate user data script file:

````bash
#!/bin/bash

# Log all output to a file for debugging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# Update system packages
yum update -y

# Install Apache web server
yum install -y httpd

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Create a simple HTML page
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Hello from Terraform on AWS</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        h1 { color: #232F3E; }
        .info { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>Hello from Terraform on AWS</h1>
    <div class="info">
        <p><strong>Instance ID:</strong> $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>
        <p><strong>Availability Zone:</strong> $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>
        <p><strong>Instance Type:</strong> $(curl -s http://169.254.169.254/latest/meta-data/instance-type)</p>
        <p><strong>Public IP:</strong> $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)</p>
    </div>
</body>
</html>
HTML

# Install AWS CLI v2 (more reliable than v1)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf awscliv2.zip aws/

# Set up log rotation to S3
cat > /etc/cron.daily/apache-log-s3 << 'CRON'
#!/bin/bash
DATE=$(date +%Y-%m-%d)
HOUR=$(date +%H)

# Upload Apache access logs to S3 with timestamp
/usr/local/bin/aws s3 cp /var/log/httpd/access_log s3://${bucket_name}/$DATE/$HOUR-access.log --region ap-south-1

# Upload Apache error logs to S3 with timestamp
/usr/local/bin/aws s3 cp /var/log/httpd/error_log s3://${bucket_name}/$DATE/$HOUR-error.log --region ap-south-1

# Optional: Clear old logs to save space (keep last 7 days)
find /var/log/httpd/ -name "*.log" -type f -mtime +7 -delete
CRON

chmod +x /etc/cron.daily/apache-log-s3

# Set up hourly log sync for more frequent uploads
cat > /etc/cron.hourly/apache-log-s3-hourly << 'CRON'
#!/bin/bash
DATE=$(date +%Y-%m-%d)
HOUR=$(date +%H)

# Sync current logs every hour
/usr/local/bin/aws s3 sync /var/log/httpd/ s3://${bucket_name}/$DATE/hourly/ --region ap-south-1 --exclude "*" --include "*.log"
CRON

chmod +x /etc/cron.hourly/apache-log-s3-hourly

# Test the web server
curl -f http://localhost/ || echo "Web server not responding"

# Test S3 access
/usr/local/bin/aws s3 ls s3://${bucket_name}/ --region ap-south-1 || echo "S3 access failed"

# Log completion
echo "Web server setup completed at $(date)" >> /var/log/user-data.log
````

## Key Improvements Made:

1. **Added Terraform version constraints** for better reproducibility
2. **Moved random_id resource** to the top to avoid dependency issues
3. **Added HTTPS support** in security group
4. **Enhanced S3 bucket configuration** with versioning and encryption
5. **Used dynamic AMI lookup** instead of hardcoded AMI ID
6. **Upgraded to t3.micro** for better performance
7. **Added EBS encryption** for the root volume
8. **Separated user data script** for better maintainability
9. **Added more comprehensive logging** and error handling
10. **Enhanced HTML page** with instance metadata
11. **Added hourly log sync** in addition to daily uploads
12. **Added more IAM permissions** for better S3 access
13. **Added comprehensive outputs** for better visibility

This configuration is more robust and follows AWS best practices while maintaining the same functionality as your original setup.

Similar code found with 1 license type