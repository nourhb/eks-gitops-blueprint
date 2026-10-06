# -----------------------------------------------------------------------------
# EKS GitOps Blueprint — provider and version constraints
# Author: Nour El Houda Bouajila (https://github.com/nourhb)
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.13.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.29.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }

  # Remote state is configured in backend.tf (S3 + DynamoDB locking).
  # Run the one-time bootstrap documented there before `terraform init`.
}
