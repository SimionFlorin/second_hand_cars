# Set AWS profile for this project
$env:AWS_PROFILE = "second-hand-cars"

# Check AWS credentials
try {
    $identity = aws sts get-caller-identity
    Write-Host "AWS Profile set to: $env:AWS_PROFILE"
    Write-Host "AWS Identity: $identity"
} catch {
    Write-Host "Error: AWS credentials not properly configured. Please run:"
    Write-Host "aws configure --profile second-hand-cars"
    Write-Host "And enter your AWS credentials."
    exit 1
}

# Check if Docker is installed and running
try {
    $dockerInfo = docker info 2>&1
    if ($dockerInfo -match "error during connect") {
        Write-Host "Error: Docker Desktop is not running. Please:"
        Write-Host "1. Open Docker Desktop"
        Write-Host "2. Wait for it to fully start (whale icon in system tray)"
        Write-Host "3. Run this script again"
        exit 1
    }
    Write-Host "Docker is running and ready"
} catch {
    Write-Host "Error: Docker is not installed or not in PATH. Please:"
    Write-Host "1. Install Docker Desktop from https://www.docker.com/products/docker-desktop"
    Write-Host "2. Start Docker Desktop"
    Write-Host "3. Run this script again"
    exit 1
}

# Initialize Terraform if not already initialized
if (-not (Test-Path ".terraform")) {
    Write-Host "Initializing Terraform..."
    terraform init
}

Write-Host "`nTerraform environment is ready. You can now run:"
Write-Host "  terraform plan    # to see planned changes"
Write-Host "  terraform apply   # to apply changes"
Write-Host "  terraform destroy # to destroy resources"

# Apply changes
terraform apply
