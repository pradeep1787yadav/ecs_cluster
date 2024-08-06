provider "aws" {
  region = var.Region
}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get default subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Create an ECS cluster
resource "aws_ecs_cluster" "drupal_cluster" {
  name = var.cluster_name
}

# Create IAM role for ECS task execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "additional_ecs_policy" {
  name        = "additionalEcsPolicy"
  description = "Additional permissions for ECS task execution"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "additional_ecs_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.additional_ecs_policy.arn
}

# Create a security group
resource "aws_security_group" "ecs_sg" {
  name        = "ecs-sg"
  description = "Allow HTTP and PostgreSQL traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
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

# Create a task definition for Drupal and PostgreSQL
resource "aws_ecs_task_definition" "drupal_task" {
  family                   = "drupal-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  cpu                      = "512"
  memory                   = "1024"
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "postgres"
      image     = "postgres"
      essential = true
      portMappings = [{
        containerPort = 5432
        hostPort      = 5432
      }]
      environment = [
        {
          name  = "POSTGRES_DB"
          value = "drupal"
        },
        {
          name  = "POSTGRES_USER"
          value = "drupal"
        },
        {
          name  = "POSTGRES_PASSWORD"
          value = "drupalpassword"
        }
      ]
    },
    {
      name      = "drupal"
      image     = "drupal:10"
      essential = true
      portMappings = [{
        containerPort = 80
        hostPort      = 80
      }]
      environment = [
        {
          name  = "DRUPAL_DB_HOST"
          value = "postgres"
        },
        {
          name  = "DRUPAL_DB_NAME"
          value = "drupal"
        },
        {
          name  = "DRUPAL_DB_USER"
          value = "drupal"
        },
        {
          name  = "DRUPAL_DB_PASSWORD"
          value = "drupalpassword"
        }
      ]
    }
  ])
}

# Create an ECS service for Drupal and PostgreSQL
resource "aws_ecs_service" "drupal_service" {
  name            = "drupal-service"
  cluster         = aws_ecs_cluster.drupal_cluster.id
  task_definition = aws_ecs_task_definition.drupal_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    assign_public_ip = true
    subnets         = data.aws_subnets.default.ids
    security_groups = [aws_security_group.ecs_sg.id]
  }
}
