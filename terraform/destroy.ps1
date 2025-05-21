# Ensure we're in the terraform directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptPath

# First, run the cleanup script
Write-Host "Running cleanup script..."
.\cleanup.ps1

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nCleanup successful. Proceeding with terraform destroy..."
    terraform destroy
} else {
    Write-Host "`nCleanup failed. Please check the errors above."
    exit 1
} 