#!/bin/bash
set -e

# Usage: ./deploy-k8s.sh [environment]
ENVIRONMENT=$1

if [ -z "$ENVIRONMENT" ]; then
    echo "Select environment:"
    echo "1) preview"
    echo "2) production"
    read -p "Enter choice [1-2]: " choice
    case $choice in
        1) ENVIRONMENT="preview";;
        2) ENVIRONMENT="production";;
        *) echo "Invalid choice"; exit 1;;
    esac
fi

if [[ "$ENVIRONMENT" != "preview" && "$ENVIRONMENT" != "production" ]]; then
    echo "Error: Environment must be 'preview' or 'production'"
    exit 1
fi

echo "Starting Kubernetes Deployment for $ENVIRONMENT..."

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
INFRASTRUCTURE_DIR="$SCRIPT_DIR/.."
TERRAFORM_DIR="$INFRASTRUCTURE_DIR/terraform"
K8S_DIR="$INFRASTRUCTURE_DIR/k8s"

# 1. Get Terraform Outputs
echo "Reading Terraform outputs..."
pushd "$TERRAFORM_DIR" > /dev/null

STATE_FILE="${ENVIRONMENT}.tfstate"
if [ ! -f "$STATE_FILE" ]; then
    echo "Error: State file '$STATE_FILE' not found. Please run deploy.sh first."
    exit 1
fi

echo "   State file found: $STATE_FILE"

# Get outputs in JSON
TF_OUTPUT_JSON=$(terraform output -state="$STATE_FILE" -json)

popd > /dev/null

# Extract Values using jq
CLUSTER_NAME=$(echo "$TF_OUTPUT_JSON" | jq -r '.gke_cluster_name.value')
LOCATION=$(echo "$TF_OUTPUT_JSON" | jq -r '.gke_location.value')
DB_IP=$(echo "$TF_OUTPUT_JSON" | jq -r '.sql_instance_ip.value')
DB_USER=$(echo "$TF_OUTPUT_JSON" | jq -r '.db_user.value')
DB_PASS=$(echo "$TF_OUTPUT_JSON" | jq -r '.db_password.value')
GEMINI_KEY=$(echo "$TF_OUTPUT_JSON" | jq -r '.gemini_api_key.value')
STATIC_IP_NAME=$(echo "$TF_OUTPUT_JSON" | jq -r '.static_ip_name.value')
MANAGED_CERT_NAME=$(echo "$TF_OUTPUT_JSON" | jq -r '.managed_cert_name.value')
DOMAIN_NAME=$(echo "$TF_OUTPUT_JSON" | jq -r '.domain_name.value')
PROJECT_ID=$(echo "$TF_OUTPUT_JSON" | jq -r '.project_id.value // empty')

if [ -z "$PROJECT_ID" ]; then
    PROJECT_ID="clestiq-petpulse"
fi

echo "   Cluster: $CLUSTER_NAME ($LOCATION)"
echo "   DB IP: $DB_IP"
echo "   Domain: $DOMAIN_NAME"

# Determine Image Repository
REPO_NAME="petpulse-${ENVIRONMENT}"
# Extract region from location (e.g., us-east1-b -> us-east1)
REGION=$(echo "$LOCATION" | sed 's/-[a-z]$//')
IMAGE_REPO="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}"

echo "   Image Repo: $IMAGE_REPO"

# 2. Convert to Connection Strings
DB_URL="postgres://${DB_USER}:${DB_PASS}@${DB_IP}:5432/petpulse"
REDIS_URL="redis://petpulse-redis:6379"

# 3. Authenticate to GKE
echo "Authenticating to GKE..."
# Check if plugin is installed (optional check, usually integrated in gcloud now or via package)
if ! gcloud components list --filter="id=gke-gcloud-auth-plugin" --format="value(state.name)" | grep -q "Installed"; then
     echo "Warning: gke-gcloud-auth-plugin might be missing."
fi

gcloud container clusters get-credentials "$CLUSTER_NAME" --location "$LOCATION"

# 4. Create/Update Secrets
echo "Configuring Secrets..."
kubectl create secret generic petpulse-secrets \
    --from-literal=DATABASE_URL="$DB_URL" \
    --from-literal=REDIS_URL="$REDIS_URL" \
    --from-literal=GEMINI_API_KEY="$GEMINI_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -

# 5. Apply Manifests
echo "Applying Kubernetes Manifests..."
# Find all yaml files in k8s dir except secret-env.yaml
find "$K8S_DIR" -name "*.yaml" -type f ! -name "secret-env.yaml" | while read -r FILE; do
    echo "   Applying $(basename "$FILE")..."
    # Replace {{IMAGE_REPO}} if it exists
    if grep -q "{{IMAGE_REPO}}" "$FILE"; then
        sed "s|{{IMAGE_REPO}}|$IMAGE_REPO|g" "$FILE" | kubectl apply -f -
    else
        kubectl apply -f "$FILE"
    fi
done

# 6. Apply Ingress
echo "Applying Ingress..."
INGRESS_TPL="$K8S_DIR/ingress.yaml.tpl"
if [ -f "$INGRESS_TPL" ]; then
    # remove trailing dot from domain if present
    NORMALIZED_DOMAIN=$(echo "$DOMAIN_NAME" | sed 's/\.$//')
    
    sed -e "s|{{STATIC_IP_NAME}}|$STATIC_IP_NAME|g" \
        -e "s|{{MANAGED_CERT_NAME}}|$MANAGED_CERT_NAME|g" \
        -e "s|{{DOMAIN_NAME}}|$NORMALIZED_DOMAIN|g" \
        "$INGRESS_TPL" | kubectl apply -f -
fi

# 7. Check Status
echo "Deployment applied. Checking Rollout status..."
kubectl rollout status deployment/petpulse-server
kubectl rollout status deployment/petpulse-processing

echo "Deployment to K8s Complete! 🚀"
