# Ensure terraform state is up to date
Write-Host "Refreshing terraform state..."
terraform refresh

# Get the repository name and URL from terraform output
try {
    $repoName = terraform output -raw ecr_repository_name
    $repoUrl = terraform output -raw ecr_repository_url
    $region = terraform output -raw aws_region

    if (-not $repoName -or -not $repoUrl -or -not $region) {
        Write-Host "Error: Required terraform outputs are not available"
        Write-Host "Please ensure terraform apply has been run successfully"
        exit 1
    }

    Write-Host "Cleaning up ECR repository: $repoName"

    # Get ECR login token and login
    Write-Host "Logging into ECR..."
    $password = aws ecr get-login-password --region $region
    $password | docker login --username AWS --password-stdin $repoUrl

    # List images first to check if there are any
    Write-Host "Listing images in repository..."
    $imagesJson = aws ecr list-images --repository-name $repoName --output json
    $images = $imagesJson | ConvertFrom-Json

    if ($images.imageIds.Count -gt 0) {
        Write-Host "Deleting all images from repository..."
        # Format image IDs properly for AWS CLI
        $imageIds = $images.imageIds | ForEach-Object {
            @{
                "imageDigest" = $_.imageDigest
                "imageTag" = $_.imageTag
            } | Where-Object { $_.Values -ne $null }
        }
        $imageIdsJson = $imageIds | ConvertTo-Json -Compress
        aws ecr batch-delete-image --repository-name $repoName --image-ids $imageIdsJson
    } else {
        Write-Host "No images found in repository"
    }

    Write-Host "Cleanup complete"
} catch {
    Write-Host "Error during cleanup: $_"
    Write-Host "Please ensure:"
    Write-Host "1. You are in the correct directory (terraform folder)"
    Write-Host "2. Terraform has been initialized (terraform init)"
    Write-Host "3. Resources have been created (terraform apply)"
    exit 1
} 