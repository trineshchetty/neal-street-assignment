# ------------------------------------------------------------------------------
# AMI Data Source — Amazon Linux 2023 (latest)
# ------------------------------------------------------------------------------
# AL2023 ships with SSM Agent pre-installed, SELinux enabled, and uses dnf
# for deterministic package management. If an ami_id override is provided
# (e.g. golden AMI pipeline), it takes precedence.
# ------------------------------------------------------------------------------

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_region" "current" {}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023.id
}

# ------------------------------------------------------------------------------
# Security Group — EC2 Instances
# ------------------------------------------------------------------------------
# Ingress: app port from ALB security group ONLY — no SSH, no public access.
# Egress: all outbound (NAT Gateway handles routing). Required for:
#   - Package installs (dnf)
#   - SSM Session Manager connectivity
#   - CloudWatch Agent log shipping
#   - Secrets Manager API calls
# ------------------------------------------------------------------------------

resource "aws_security_group" "ec2" {
  name_prefix = "${var.project}-${var.environment}-ec2-"
  description = "Security group for rewards web tier EC2 instances"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-ec2-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "ec2_from_alb" {
  security_group_id            = aws_security_group.ec2.id
  description                  = "Allow app traffic from ALB only"
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.alb_security_group_id

  tags = merge(var.tags, {
    Name = "alb-to-ec2"
  })
}

resource "aws_vpc_security_group_egress_rule" "ec2_all_outbound" {
  security_group_id = aws_security_group.ec2.id
  description       = "Allow all outbound (via NAT for internet)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(var.tags, {
    Name = "all-outbound"
  })
}

# ------------------------------------------------------------------------------
# IAM Role — EC2 Instance Profile
# ------------------------------------------------------------------------------
# Least-privilege policies for:
#   1. SSM Session Manager (shell access, no SSH keys needed)
#   2. CloudWatch Agent (log shipping + basic metrics)
#   3. Secrets Manager (read APP_SECRET only)
# ------------------------------------------------------------------------------

resource "aws_iam_role" "ec2" {
  name = "${var.project}-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# SSM Session Manager — replaces SSH access entirely
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch Agent — log shipping and basic metrics
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Secrets Manager — scoped to the specific secret ARN
resource "aws_iam_role_policy" "secrets_access" {
  name = "secrets-manager-read"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = var.secrets_manager_arn != "" ? [var.secrets_manager_arn] : ["*"]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2.name

  tags = var.tags
}

# ------------------------------------------------------------------------------
# Launch Template
# ------------------------------------------------------------------------------
# IMDSv2 enforced (http_tokens = required) — prevents SSRF-based credential
# theft. This is an AWS Well-Architected security baseline requirement.
# No key pair — access is via SSM Session Manager only.
# ------------------------------------------------------------------------------

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project}-${var.environment}-app-"
  image_id      = local.ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  vpc_security_group_ids = [aws_security_group.ec2.id]

  # Enforce IMDSv2 — blocks IMDSv1 requests entirely
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # EBS root volume — encrypted by default, gp3 for cost efficiency
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(var.tags, {
      Name = "${var.project}-${var.environment}-rewards"
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(var.tags, {
      Name = "${var.project}-${var.environment}-rewards-vol"
    })
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-app-lt"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------------------
# EC2 Instances
# ------------------------------------------------------------------------------
# Using count for simplicity. Scale out by increasing var.instance_count.
# Each instance is placed in the private subnet with no public IP.
# The ALB in the public subnet handles all inbound traffic.
# ------------------------------------------------------------------------------

resource "aws_instance" "app" {
  count = var.instance_count

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  subnet_id = var.private_subnet_id

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-rewards-${count.index + 1}"
  })
}
