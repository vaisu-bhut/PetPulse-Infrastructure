# PetPulse Infrastructure

This directory contains the Terraform configuration for the PetPulse infrastructure on Google Cloud Platform.

## Directory Structure

- `terraform/`: Contains all Terraform configuration files.
    - `main.tf`: Core resources (VPC, GKE, Cloud SQL, Secrets).
    - `variables.tf`: Variable definitions (no defaults).
    - `outputs.tf`: Output definitions.
    - `providers.tf`: Provider configuration.
    - `preview.tfvars`: Configuration for the Preview environment.
    - `production.tfvars`: Configuration for the Production environment.
- `deploy.sh`: Bash script to deploy the infrastructure.
- `deploy.ps1`: PowerShell script to deploy the infrastructure.

## Prerequisites

- Terraform >= 1.0
- Google Cloud SDK (gcloud) installed and authenticated.
- Access to the GCP Project `clestiq-petpulse`.

## Usage

### Using Bash (Linux/Mac/Git Bash)

To deploy to preview:
```bash
./deploy.sh preview
```

To deploy to production:
```bash
./deploy.sh production
```

### Using PowerShell (Windows)

To deploy to preview:
```powershell
.\deploy.ps1 -Environment preview
```

To deploy to production:
```powershell
.\deploy.ps1 -Environment production
```

## State Management

State files are stored locally in the `terraform/` directory as `${environment}.tfstate`.
**IMPORTANT**: Do not commit state files or `.tfvars` containing secrets to version control.