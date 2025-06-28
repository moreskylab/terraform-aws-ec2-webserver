provider "aws" {
  region = "ap-south-1"
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

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
}

# Create an S3 bucket for logs
resource "aws_s3_bucket" "logs" {
  bucket = "tf-web-server-logs-${random_id.suffix.hex}"

  tags = {
    Name = "tf-web-server-logs"
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

# Create an EC2 instance
resource "aws_instance" "web" {
  ami                    = "ami-0d03cb826412c6b0f"  # Amazon Linux 2 AMI
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = "ap-south-1"
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "Hello from Terraform" > /var/www/html/index.html

    # Install AWS CLI for S3 log upload
    yum install -y aws-cli

    # Set up log rotation to S3
    cat > /etc/cron.daily/apache-log-s3 << 'CRON'
    #!/bin/bash
    DATE=$(date +%Y-%m-%d)
    aws s3 cp /var/log/httpd/access_log s3://${aws_s3_bucket.logs.bucket}/\$DATE/access.log
    CRON

    chmod +x /etc/cron.daily/apache-log-s3
  EOF

  tags = {
    Name = "tf-web-server"
  }
}

# Generate a random suffix for global uniqueness
resource "random_id" "suffix" {
  byte_length = 4
}

# Output the web server's public IP
output "web_server_public_ip" {
  value = aws_instance.web.public_ip
}

# Output the S3 bucket name
output "logs_bucket" {
  value = aws_s3_bucket.logs.bucket
}