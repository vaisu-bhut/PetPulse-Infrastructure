# Deploy Script for Windows (PowerShell)
param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("preview", "production")]
    [string]$Environment
)

$ErrorActionPreference = "Stop"

Write-Host "Deploying to $Environment environment..."

$TerraformDir = Join-Path $PSScriptRoot "..\terraform"
Set-Location $TerraformDir

# Format check
Write-Host "Running terraform fmt check..."
terraform fmt -check
if ($LASTEXITCODE -ne 0) { throw "Terraform format check failed" }

# Init
Write-Host "Running terraform init..."
terraform init

# Plan
Write-Host "Running terraform plan..."
terraform plan -var-file="${Environment}.tfvars" -state="${Environment}.tfstate" -out="${Environment}.plan"

# Ask for confirmation
$confirmation = Read-Host "Do you want to proceed with apply? (yes/no)"
if ($confirmation -ne "yes" -and $confirmation -ne "y") {
    Write-Host "Deployment cancelled."
    exit
}

# Apply
Write-Host "Running terraform apply..."
terraform apply -state="${Environment}.tfstate" "${Environment}.plan"

Set-Location ..

Write-Host "Deployment to $Environment complete!"
