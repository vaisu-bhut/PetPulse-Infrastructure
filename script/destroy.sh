#!/bin/bash
set -e

# Usage: ./destroy.sh [environment]
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

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

cd "$TERRAFORM_DIR"

# Confirmation
echo "WARNING: You are about to DESTROY all resources for $ENVIRONMENT."
read -p "Type 'destroy' to confirm: " confirmation
if [ "$confirmation" != "destroy" ]; then
    echo "Destruction cancelled."
    exit 0
fi

echo "Starting destruction process for $ENVIRONMENT..."

# 1. Try to Authenticate to GKE to clean up resources
echo "Attempting to authenticate to GKE for cleanup..."
STATE_FILE="${ENVIRONMENT}.tfstate"

if [ -f "$STATE_FILE" ]; then
    set +e # Allow errors during cleanup
    
    TF_OUTPUT_JSON=$(terraform output -state="$STATE_FILE" -json)
    if [ $? -eq 0 ]; then
        CLUSTER_NAME=$(echo "$TF_OUTPUT_JSON" | jq -r '.gke_cluster_name.value')
        LOCATION=$(echo "$TF_OUTPUT_JSON" | jq -r '.gke_location.value')
        
        if [[ -n "$CLUSTER_NAME" && "$CLUSTER_NAME" != "null" && -n "$LOCATION" && "$LOCATION" != "null" ]]; then
            echo "   Cluster found in state: $CLUSTER_NAME ($LOCATION)"
            
            # Authenticate
            gcloud container clusters get-credentials "$CLUSTER_NAME" --location "$LOCATION"
            
            # 2. Delete Ingress causing SSL locks
            echo "   Deleting Ingress and Services to free up SSL/LoadBalancers..."
            kubectl delete ingress --all --all-namespaces --timeout=30s
            kubectl delete service --all --all-namespaces --timeout=30s
            
             # 3. Delete Workloads causing DB locks
            echo "   Deleting Deployments/Pods/PVCs to free up Database and Disks..."
            kubectl delete pvc --all --all-namespaces --timeout=30s
            kubectl delete deployment,statefulset,daemonset,job --all --all-namespaces --timeout=30s
            
            # 4. Wait for GCLB
            echo "   Waiting 30 seconds for Cloud Load Balancers to release..."
            sleep 30
        fi
    fi
    set -e
else
    echo "Warning: State file not found, skipping pre-cleanup."
fi

# 5. Disable Deletion Protection
if [[ -n "$CLUSTER_NAME" && "$CLUSTER_NAME" != "null" ]]; then
     echo "   Ensuring deletion protection is disabled..."
     # Ignore errors with || true
     gcloud container clusters update "$CLUSTER_NAME" --no-enable-deletion-protection --location "$LOCATION" 2>/dev/null || true
fi

# 6. Destroy Infrastructure
echo "Running terraform destroy..."
if ! terraform destroy -var-file="${ENVIRONMENT}.tfvars" -state="${ENVIRONMENT}.tfstate" -auto-approve; then
    echo "Terraform destroy failed. Checking for stuck VPC peering..."
    
    # Attempt to delete the stuck peering connection which often blocks VPC deletion
    # The name is typically 'servicenetworking-googleapis-com'
    PEERING_NAME="servicenetworking-googleapis-com"
    NETWORK_NAME="${ENVIRONMENT}-vpc"
    
    echo "Attempting to force delete peering '$PEERING_NAME' from '$NETWORK_NAME'..."
    if gcloud compute networks peerings delete "$PEERING_NAME" --network="$NETWORK_NAME" --quiet; then
        echo "Peering deletion initiated. Waiting 10s for propagation..."
        sleep 10
    else
        echo "Warning: Could not delete peering manually. It might already be gone or requires other cleanup."
    fi

    echo "Retrying terraform destroy to clean up remaining resources (VPC, etc)..."
    terraform destroy -var-file="${ENVIRONMENT}.tfvars" -state="${ENVIRONMENT}.tfstate" -auto-approve
fi

echo "Destruction of $ENVIRONMENT complete!"
