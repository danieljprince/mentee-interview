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
data "aws_vpc" "default" {
  default = true
}
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

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
  thumbprint_list = ["ab9d0263244dd0326eb67015705a667e79cfe998"]
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

resource "aws_iam_role_policy_attachment" "github_actions_ecs_full" {
  role       = aws_iam_role.github_actions_ecr.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

# 4. IAM Task Execution Role for ECS Fargate
resource "aws_iam_role" "ecs_task_execution" {
  name                 = "exam-ecs-task-execution-role"
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/candidate-exam-boundary"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 5. Security Group allowing HTTP traffic on port 8080
resource "aws_security_group" "ecs_sg" {
  name        = "mentee-interview-sg"
  description = "Allow HTTP inbound traffic on port 8080"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 6. Amazon ECS Fargate Cluster, Task Definition & Service
resource "aws_ecs_cluster" "main" {
  name = "mentee-interview-cluster"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "mentee-interview-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "mentee-interview"
      image     = "${aws_ecr_repository.app.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "mentee-interview-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
}
