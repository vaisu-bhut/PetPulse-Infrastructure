# Deploy-K8s.ps1
param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("preview", "production")]
    [string]$Environment
)

$ErrorActionPreference = "Stop"

# Paths
$ScriptDir = $PSScriptRoot
$InfrastructureDir = Join-Path $ScriptDir ".."
$TerraformDir = Join-Path $InfrastructureDir "terraform"
$K8sDir = Join-Path $InfrastructureDir "k8s"

Write-Host "Starting Kubernetes Deployment for $Environment..." -ForegroundColor Cyan

# 1. Get Terraform Outputs
Write-Host "Reading Terraform outputs..."
Push-Location $TerraformDir

try {
    # Ensure state is selected (if using workspaces, though here we use -state file)
    # The previous scripts used -state="${Environment}.tfstate"
    # We must point to that specific state file to get outputs
    
    $StateFile = "${Environment}.tfstate"
    if (-not (Test-Path $StateFile)) {
        throw "State file '$StateFile' not found. Please run deploy.ps1 first."
    }
    
    # Debug: Check file existence
    Write-Host "   State file found: $StateFile" -ForegroundColor DarkGray

    # Use explicit argument list for safety
    # Note: terraform output -state=FILE -json
    $TFOutputJson = & terraform output "-state=$StateFile" -json
    
    if ($LASTEXITCODE -ne 0) {
        throw "Terraform command failed."
    }

    # Debug: Print raw (truncated)
    # Write-Host "   Raw Output: $($TFOutputJson.Substring(0, [System.Math]::Min(100, $TFOutputJson.Length)))..." -ForegroundColor DarkGray

    $TFOutput = $TFOutputJson | ConvertFrom-Json
} catch {
    Write-Error "Failed to read Terraform outputs: $_"
    # Print raw output if available for debugging
    if ($TFOutputJson) { Write-Host "JSON content: $TFOutputJson" -ForegroundColor Red }
    Pop-Location
    exit 1
}
Pop-Location

# Extract Values
$ClusterName = $TFOutput.gke_cluster_name.value
# Use location (which handles region or zone appropriately)
$Location = $TFOutput.gke_location.value
$DbIp = $TFOutput.sql_instance_ip.value
$DbUser = $TFOutput.db_user.value
$DbPass = $TFOutput.db_password.value
$GeminiKey = $TFOutput.gemini_api_key.value

Write-Host "   Cluster: $ClusterName ($Location)"
Write-Host "   DB IP: $DbIp"

# 2. Convert to Connection Strings
$DbUrl = "postgres://${DbUser}:${DbPass}@${DbIp}:5432/petpulse"
# Redis is internal K8s DNS
$RedisUrl = "redis://petpulse-redis:6379"

# 3. Authenticate to GKE
Write-Host "Authenticating to GKE..."
# Ensure auth plugin is installed
$PluginCheck = gcloud components list --filter="id=gke-gcloud-auth-plugin" --format="value(state.name)"
if ($PluginCheck -ne "Installed") {
    Write-Warning "The 'gke-gcloud-auth-plugin' is required but not installed."
    Write-Warning "Auto-installation is failing due to environment restrictions."
    Write-Warning "Please run the following command manually in your terminal:"
    Write-Host "    gcloud components install gke-gcloud-auth-plugin" -ForegroundColor Yellow
    throw "Missing required component: gke-gcloud-auth-plugin. Please install manually and retry."
}

# Use --location to support both regional and zonal clusters agnostic of variable name
gcloud container clusters get-credentials $ClusterName --location $Location

# 4. Create/Update Secrets
Write-Host "Configuring Secrets..."
# We use --from-literal for safety, piping to apply to handle updates
# Notes: PowerShell string interpolation works well here.
$SecretCmd = "kubectl create secret generic petpulse-secrets " + `
             "--from-literal=DATABASE_URL='$DbUrl' " + `
             "--from-literal=REDIS_URL='$RedisUrl' " + `
             "--from-literal=GEMINI_API_KEY='$GeminiKey' " + `
             "--dry-run=client -o yaml | kubectl apply -f -"

Invoke-Expression $SecretCmd

# 5. Apply Manifests
Write-Host "Applying Kubernetes Manifests..."
$Manifests = Get-ChildItem $K8sDir -Filter "*.yaml" | Where-Object { $_.Name -ne "secret-env.yaml" }

foreach ($File in $Manifests) {
    Write-Host "   Applying $($File.Name)..."
    kubectl apply -f $File.FullName
}

# 6. Check Status
Write-Host "Deployment applied. Checking Rollout status..."
kubectl rollout status deployment/petpulse-server
kubectl rollout status deployment/petpulse-processing

Write-Host "Deployment to K8s Complete! 🚀" -ForegroundColor Green
