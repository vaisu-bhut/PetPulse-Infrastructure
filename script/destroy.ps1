# Destroy Script for Windows (PowerShell)
param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("preview", "production")]
    [string]$Environment
)

$ErrorActionPreference = "Stop"

$TerraformDir = Join-Path $PSScriptRoot "..\terraform"
Set-Location $TerraformDir

# Confirmation
$confirmation = Read-Host "WARNING: You are about to DESTROY all resources for $Environment. Type 'destroy' to confirm"
if ($confirmation -ne "destroy") {
    Write-Host "Destruction cancelled."
    exit
}

Write-Host "Starting destruction process for $Environment..." -ForegroundColor Cyan

# 1. Try to Authenticate to GKE to clean up resources
Write-Host "Attempting to authenticate to GKE for cleanup..."
try {
    $StateFile = "${Environment}.tfstate"
    if (Test-Path $StateFile) {
        $TFOutputJson = & terraform output "-state=$StateFile" -json
        if ($LASTEXITCODE -eq 0) {
            $TFOutput = $TFOutputJson | ConvertFrom-Json
            $ClusterName = $TFOutput.gke_cluster_name.value
            $Location = $TFOutput.gke_location.value

            if ($ClusterName -and $Location) {
                 Write-Host "   Cluster found in state: $ClusterName ($Location)"
                 # Authenticate
                 gcloud container clusters get-credentials $ClusterName --location $Location
                 
                 # 2. Delete Ingress causing SSL locks
                 Write-Host "   Deleting Ingress and Services to free up SSL/LoadBalancers..."
                 kubectl delete ingress --all --all-namespaces --timeout=30s
                 kubectl delete service --all --all-namespaces --timeout=30s

                 # 3. Delete Workloads causing DB locks
                 Write-Host "   Deleting Deployments/Pods to free up Database..."
                 kubectl delete deployment,statefulset,daemonset,job --all --all-namespaces --timeout=30s
                 
                 # 4. Wait for GCLB to potentially spin down (crucial)
                 Write-Host "   Waiting 30 seconds for Cloud Load Balancers to release..." -ForegroundColor Yellow
                 Start-Sleep -Seconds 30
            }
        }
    }
} catch {
    Write-Warning "Failed to perform Kubernetes cleanup: $_"
    Write-Warning "Continuing to Terraform destroy... (This might fail if resources are locked)"
}

# 5. Disable Deletion Protection (Just in case)
try {
    if ($ClusterName) {
        Write-Host "   Ensuring deletion protection is disabled..."
        # Attempt via gcloud, ignore error if fails (might already be deleted or flags differ)
        gcloud container clusters update $ClusterName --no-enable-deletion-protection --location $Location 2>$null
    }
} catch {}

# 6. Destroy
Write-Host "Running terraform destroy..."
terraform destroy -var-file="${Environment}.tfvars" -state="${Environment}.tfstate" -auto-approve

Set-Location ..

Write-Host "Destruction of $Environment complete!" -ForegroundColor Green
