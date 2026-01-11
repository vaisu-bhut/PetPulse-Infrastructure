# Destroy Script for Windows (PowerShell)
param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("preview", "production")]
    [string]$Environment
)

$ErrorActionPreference = "Stop"

Write-Host "Destroying infrastructure for $Environment environment..."

Set-Location terraform

# Confirmation
$confirmation = Read-Host "WARNING: You are about to DESTROY all resources for $Environment. Type 'destroy' to confirm"
if ($confirmation -ne "destroy") {
    Write-Host "Destruction cancelled."
    exit
}

# Destroy
Write-Host "Running terraform destroy..."
terraform destroy -var-file="${Environment}.tfvars" -state="${Environment}.tfstate"

Set-Location ..

Write-Host "Destruction of $Environment complete!"
