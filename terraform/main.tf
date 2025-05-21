terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "second-hand-cars"
  shared_credentials_files = ["~/.aws/credentials"]
  shared_config_files      = ["~/.aws/config"]
}

locals {
  resource_prefix = "${var.project_prefix}-${var.environment}"
  common_tags = {
    Environment = var.environment
    Project     = var.project_prefix
    ManagedBy   = "terraform"
  }
}

# S3 Buckets
resource "aws_s3_bucket" "landing_zone" {
  bucket = "${local.resource_prefix}-landing-zone"
  tags   = local.common_tags
}

resource "aws_s3_bucket" "curated_zone" {
  bucket = "${local.resource_prefix}-curated-zone"
  tags   = local.common_tags
}

# Enable bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "landing_zone" {
  bucket = aws_s3_bucket.landing_zone.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "curated_zone" {
  bucket = aws_s3_bucket.curated_zone.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ECR repository for Lambda container image
resource "aws_ecr_repository" "processor_repo" {
  name                 = "${local.resource_prefix}-processor"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags                 = local.common_tags

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ECR lifecycle policy to automatically delete old images
resource "aws_ecr_lifecycle_policy" "processor_repo_policy" {
  repository = aws_ecr_repository.processor_repo.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus     = "any"
        countType     = "imageCountMoreThan"
        countNumber   = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# Build & push the Docker image locally
resource "null_resource" "build_and_push_image" {
  depends_on = [aws_ecr_lifecycle_policy.processor_repo_policy]
  
  triggers = {
    # Force rebuild by adding timestamp
    timestamp       = timestamp()
    dockerfile_hash = filesha256("${path.module}/../Dockerfile")
    req_hash        = filesha256("${path.module}/../requirements.txt")
    src_hash        = join(",", [
      filesha256("${path.module}/../src/lambda_function.py")
    ])
  }

  provisioner "local-exec" {
    command = <<EOT
      $ErrorActionPreference = "Stop"
      $password = aws ecr get-login-password --region ${var.aws_region} --profile second-hand-cars
      if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to get ECR login password"
        exit 1
      }
      docker login --username AWS --password $password ${aws_ecr_repository.processor_repo.repository_url}
      if ($LASTEXITCODE -ne 0) {
        Write-Error "Docker login to ECR failed"
        exit 1
      }
      
      # Untag existing latest image to avoid conflicts. Handle error if image does not exist.
      try {
        aws ecr batch-delete-image --repository-name ${aws_ecr_repository.processor_repo.name} --image-ids imageTag=latest --region ${var.aws_region} --profile second-hand-cars --no-cli-pager
        Write-Host "Successfully deleted existing 'latest' tag (if it existed)."
      } catch {
        Write-Host "Could not delete existing 'latest' tag (it might not exist, or another error occurred). Continuing... Error: $($_.Exception.Message)"
      }

      # Build and push the image with explicit platform for Lambda compatibility
      docker build --platform linux/amd64 -t ${aws_ecr_repository.processor_repo.repository_url}:latest ../
      $push_output = docker push ${aws_ecr_repository.processor_repo.repository_url}:latest 2>&1
      Write-Host "Docker push output: $push_output"
      if ($LASTEXITCODE -ne 0) {
        Write-Error "Docker push failed: $push_output"
        exit 1
      }
      $digest = $push_output | Select-String -Pattern 'digest: (sha256:[0-9a-f]{64})' | ForEach-Object { $_.Matches[0].Groups[1].Value }
      if (-not $digest) {
        Write-Error "Could not extract digest from push output: $push_output"
        exit 1
      }
      $digest | Out-File -FilePath "${path.module}/.ecr_image_digest.txt" -Encoding ascii -Force
      Write-Host "Image digest $digest written to .ecr_image_digest.txt"
    EOT
    interpreter = ["powershell", "-Command"]
  }
}

data "local_file" "image_digest" {
  depends_on = [null_resource.build_and_push_image]
  filename = "${path.module}/.ecr_image_digest.txt"
}

# Lambda function using container image
resource "aws_lambda_function" "processor" {
  depends_on    = [null_resource.build_and_push_image, data.local_file.image_digest]
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.processor_repo.repository_url}@${data.local_file.image_digest.content}"
  function_name = "${local.resource_prefix}-data-processor"
  role          = aws_iam_role.lambda_role.arn
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  architectures = ["x86_64"]

  environment {
    variables = {
      CURATED_BUCKET = aws_s3_bucket.curated_zone.id
      ENVIRONMENT    = var.environment
    }
  }

  tags = local.common_tags
}

# S3 trigger for Lambda
resource "aws_s3_bucket_notification" "landing_zone_trigger" {
  bucket = aws_s3_bucket.landing_zone.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".csv"
  }
}

# Lambda permission to allow S3 invocation
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.landing_zone.arn
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${local.resource_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.resource_prefix}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = ["${aws_s3_bucket.landing_zone.arn}/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = ["${aws_s3_bucket.curated_zone.arn}/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = ["arn:aws:logs:*:*:*"]
      },
      {
        "Effect": "Allow",
        "Action": [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ],
        "Resource": "${aws_ecr_repository.processor_repo.arn}"
      }
    ]
  })
}

# Outputs
output "landing_zone_bucket" {
  description = "Name of the landing zone S3 bucket"
  value       = aws_s3_bucket.landing_zone.id
}

output "curated_zone_bucket" {
  description = "Name of the curated zone S3 bucket"
  value       = aws_s3_bucket.curated_zone.id
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.processor.function_name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.processor_repo.repository_url
}

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.processor_repo.name
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
} 