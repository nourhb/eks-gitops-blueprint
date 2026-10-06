# -----------------------------------------------------------------------------
# EKS GitOps Blueprint — remote state backend (S3 + DynamoDB locking)
# Author: Nour El Houda Bouajila (https://github.com/nourhb)
#
# Why: a local terraform.tfstate does not survive CI runners, laptops being
# lost, or two engineers running `apply` at the same time. The S3 backend
# stores the state durably (versioned, encrypted); the DynamoDB table gives
# Terraform a distributed lock so concurrent runs fail fast instead of
# corrupting state.
#
# Backend blocks cannot use variables — the values below are literals.
# They match the defaults of var.state_bucket_name / var.state_lock_table.
# If you rename them, update both places.
#
# BOOTSTRAP (run once, before `terraform init`):
#
#   aws s3api create-bucket --bucket eks-gitops-blueprint-tfstate \
#     --region ca-central-1 \
#     --create-bucket-configuration LocationConstraint=ca-central-1
#   aws s3api put-bucket-versioning --bucket eks-gitops-blueprint-tfstate \
#     --versioning-configuration Status=Enabled
#   aws s3api put-bucket-encryption --bucket eks-gitops-blueprint-tfstate \
#     --server-side-encryption-configuration \
#     '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
#   aws dynamodb create-table --table-name eks-gitops-blueprint-locks \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --billing-mode PAY_PER_REQUEST --region ca-central-1
# -----------------------------------------------------------------------------

terraform {
  backend "s3" {
    bucket         = "eks-gitops-blueprint-tfstate"
    key            = "blueprint/terraform.tfstate"
    region         = "ca-central-1"
    dynamodb_table = "eks-gitops-blueprint-locks"
    encrypt        = true
  }
}
