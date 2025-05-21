# Second-Hand Cars Price Prediction System

This project implements an automated car price prediction system using AWS services. The system processes car sales data through a serverless pipeline and trains a machine learning model to predict car prices.

## Architecture Overview

The system consists of the following components:

1. S3 Landing Zone - Raw data ingestion bucket
2. Lambda Function - Data preprocessing and validation
3. S3 Curated Zone - Cleaned and processed data bucket
4. Jupyter Notebook - Model training and evaluation

## Prerequisites

- AWS CLI installed and configured
- Terraform >= 1.0.0
- Python >= 3.8
- AWS account with appropriate permissions

## Project Structure

```
.
├── terraform/           # Infrastructure as Code
├── src/                 # Lambda function source code
├── notebooks/          # Jupyter notebooks for model training
├── .aws/               # Project-specific AWS configuration
├── setup.ps1           # Project environment setup script
└── README.md           # This file
```

## AWS Configuration

This project uses a project-specific AWS profile for better security and isolation. Follow these steps to set up your AWS configuration:

1. Configure the project-specific AWS profile:
   ```bash
   aws configure --profile second-hand-cars
   ```
   You'll be prompted to enter:
   - AWS Access Key ID
   - AWS Secret Access Key
   - Default region (eu-central-1)
   - Default output format (json)

2. Set up the project environment:
   ```powershell
   .\setup.ps1
   ```
   This script sets the AWS profile and verifies your identity.

3. Verify the configuration:
   ```bash
   aws sts get-caller-identity
   ```

Note: The `.aws` directory is gitignored to prevent accidental credential exposure.

## Required Variables

The following variables must be provided when deploying the infrastructure:

1. `aws_region` - AWS region to deploy resources (e.g., us-east-1)
2. `project_prefix` - Prefix for all resource names (lowercase, numbers, hyphens only)
3. `environment` - Deployment environment (dev, staging, or prod)

Optional variables with defaults:
- `lambda_memory_size` - Memory allocation for Lambda function (default: 512 MB)
- `lambda_timeout` - Lambda function timeout (default: 300 seconds)

## Deployment Instructions

1. Create a `terraform.tfvars` file with required variables:
   ```hcl
   aws_region     = "us-east-1"
   project_prefix = "car-price-pred"
   environment    = "dev"
   ```

2. Set up the Terraform environment:
   ```powershell
   cd terraform
   .\setup.ps1
   ```
   This script will:
   - Set the AWS profile to "second-hand-cars"
   - Verify your AWS identity
   - Initialize Terraform if needed

3. Review the planned changes:
   ```bash
   terraform plan
   ```

4. Deploy the infrastructure:
   ```bash
   terraform apply
   ```

5. After deployment, note the following outputs:
   - Landing zone S3 bucket name
   - Curated zone S3 bucket name
   - Lambda function name

## Data Processing Pipeline

The Lambda function automatically triggers when a new CSV file is uploaded to the landing zone S3 bucket. It performs the following operations:
- Removes irrelevant attributes
- Removes rows with missing critical data
- Handles imputable missing values
- Saves processed data to the curated zone

## Machine Learning Model

The Jupyter notebook in the `notebooks` directory demonstrates:
- Loading data from the curated zone
- Feature engineering and preprocessing
- Model training and evaluation
- Price prediction with a bias towards slight underestimation

## Cleanup

To destroy the created resources:
```bash
cd terraform
terraform destroy
```

## Security Note

- The S3 buckets are encrypted by default
- IAM roles follow the principle of least privilege
- No sensitive data is stored in the code repository
- Resources are tagged for better organization and cost tracking
- AWS credentials are managed through project-specific profiles