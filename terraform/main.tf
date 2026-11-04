terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-west-2"
}

variable "github_repo" {
  description = "GitHub owner/repo pattern for OIDC trust"
  type        = string
  default     = "danieljprince*/mentee-interview*"
}

data "aws_caller_identity" "current" {}

# 1. Amazon ECR Repository
resource "aws_ecr_repository" "app" {
  name                 = "mentee-interview-registry"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# 2. GitHub OIDC Identity Provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# 3. IAM Role for GitHub Actions (with exam-* prefix & candidate-exam-boundary)
resource "aws_iam_role" "github_actions_ecr" {
  name                 = "exam-github-actions-ecr"
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/candidate-exam-boundary"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr_poweruser" {
  role       = aws_iam_role.github_actions_ecr.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

# 4. IAM Role for AWS App Runner to pull from ECR
resource "aws_iam_role" "apprunner_ecr_access" {
  name                 = "exam-apprunner-ecr-access"
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/candidate-exam-boundary"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "build.apprunner.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "apprunner_ecr_policy" {
  role       = aws_iam_role.apprunner_ecr_access.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

# 5. AWS App Runner Service (auto-deploys whenever :latest is pushed to ECR)
resource "aws_apprunner_service" "app" {
  service_name = "mentee-interview-service"

  source_configuration {
    authentication_configuration {
      access_role_arn = aws_iam_role.apprunner_ecr_access.arn
    }
    image_repository {
      image_identifier      = "${aws_ecr_repository.app.repository_url}:latest"
      image_repository_type = "ECR"
      image_configuration {
        port = "8080"
      }
    }
    auto_deployments_enabled = true
  }

  health_check_configuration {
    protocol = "HTTP"
    path     = "/health"
  }
}

output "service_url" {
  description = "Live URL of the deployed App Runner service"
  value       = "https://${aws_apprunner_service.app.service_url}"
}
