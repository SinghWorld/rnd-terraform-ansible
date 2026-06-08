###############################################################
# main.tf
# Windows EC2 — us-east-1, default VPC
# WinRM fully working for Ansible / local testing
###############################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

###############################################################
# 1. KEY PAIR — generated locally, public key pushed to AWS
###############################################################

resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2_key" {
  key_name   = var.key_name
  public_key = tls_private_key.ec2_key.public_key_openssh

  tags = local.common_tags
}

# Save the private key to disk so you can RDP / decrypt password
resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.ec2_key.private_key_pem
  filename        = "${path.module}/../scripts/${var.key_name}.pem"
  file_permission = "0600"
}

###############################################################
# 2. DATA SOURCES — default VPC / subnet / latest AMI
###############################################################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Always use the latest Windows Server 2022 Base AMI
data "aws_ami" "windows" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

###############################################################
# 3. SECURITY GROUP — WinRM (5985/5986) + RDP (3389)
###############################################################

resource "aws_security_group" "windows" {
  name        = "${var.project_name}-sg"
  description = "Windows EC2 - WinRM and RDP access"
  vpc_id      = data.aws_vpc.default.id

  # WinRM HTTP — Ansible connects here
  ingress {
    description = "WinRM HTTP"
    from_port   = 5985
    to_port     = 5985
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict to your IP in production
  }

  # WinRM HTTPS
  ingress {
    description = "WinRM HTTPS"
    from_port   = 5986
    to_port     = 5986
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # RDP — manual console access
  ingress {
    description = "RDP"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-sg" })
}

###############################################################
# 4. EC2 INSTANCE
###############################################################

resource "aws_instance" "windows" {
  ami                         = data.aws_ami.windows.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.ec2_key.key_name
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.windows.id]
  associate_public_ip_address = true

  # CRITICAL: This userdata script is what makes WinRM work
  user_data = file("${path.module}/userdata.ps1")

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-windows" })

  # Give Windows enough time to fully boot + run userdata
  timeouts {
    create = "15m"
  }
}

###############################################################
# 5. LOCALS
###############################################################

locals {
  common_tags = {
    Project     = var.project_name
    Environment = "dev"
    ManagedBy   = "Terraform"
    OS          = "Windows-2022"
  }
}
