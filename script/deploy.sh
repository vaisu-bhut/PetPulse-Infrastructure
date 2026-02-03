#!/bin/bash
set -e

# Usage: ./deploy.sh [environment]
ENVIRONMENT=$1
PROJECT_ID="petpulse-485420" 
gcloud config set project "$PROJECT_ID"

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

echo "Deploying to $ENVIRONMENT environment..."

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

cd "$TERRAFORM_DIR"

# Build Cloud Function zip from PetPulse-Serverless
echo "Building email-sender function from PetPulse-Serverless..."
SERVERLESS_DIR="$SCRIPT_DIR/../../PetPulse-Serverless"
if [ ! -d "$SERVERLESS_DIR" ]; then
    echo "Error: PetPulse-Serverless directory not found at $SERVERLESS_DIR"
    exit 1
fi
(cd "$SERVERLESS_DIR" && zip -q -r "$TERRAFORM_DIR/email-sender.zip" index.js package.json)
echo "✅ email-sender.zip created"

# Format check
echo "Running terraform fmt check..."
terraform fmt -check

# Init
echo "Running terraform init..."
terraform init

# Plan
echo "Running terraform plan..."
terraform plan -var-file="${ENVIRONMENT}.tfvars" -state="${ENVIRONMENT}.tfstate" -out="${ENVIRONMENT}.plan"

# Ask for confirmation
read -p "Do you want to proceed with apply? (yes/no) " confirmation
if [[ "$confirmation" != "yes" && "$confirmation" != "y" ]]; then
    echo "Deployment cancelled."
    exit 0
fi

# Apply
echo "Running terraform apply..."
terraform apply -state="${ENVIRONMENT}.tfstate" "${ENVIRONMENT}.plan"

echo "Deployment to $ENVIRONMENT complete!"
