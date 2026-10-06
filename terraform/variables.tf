# -----------------------------------------------------------------------------
# EKS GitOps Blueprint — input variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Prefix used for naming all resources created by this blueprint."
  type        = string
  default     = "blueprint"
}

variable "aws_region" {
  description = "AWS region where the infrastructure is deployed. Defaults to ca-central-1 (Canada)."
  type        = string
  default     = "ca-central-1"
}

variable "environment" {
  description = "Environment label applied to resource tags (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to spread subnets across. Must match the chosen region."
  type        = list(string)
  default     = ["ca-central-1a", "ca-central-1b", "ca-central-1d"]
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS control plane and managed node group."
  type        = string
  default     = "1.29"
}

variable "node_instance_types" {
  description = "EC2 instance types for the EKS managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}

variable "enable_nat_gateway" {
  description = "Create a NAT gateway so private subnets can reach the internet (required for pulling images). Disable to save cost in throwaway environments."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single shared NAT gateway instead of one per AZ. Cheaper, slightly less resilient."
  type        = bool
  default     = true
}

variable "argocd_chart_version" {
  description = "Version of the Argo CD Helm chart to install."
  type        = string
  default     = "5.51.6"
}

variable "alb_controller_chart_version" {
  description = "Version of the AWS Load Balancer Controller Helm chart to install."
  type        = string
  default     = "1.7.1"
}

variable "karpenter_chart_version" {
  description = "Version of the Karpenter Helm chart (OCI) to install."
  type        = string
  default     = "0.32.1"
}

variable "monitoring_chart_version" {
  description = "Version of the kube-prometheus-stack Helm chart to install."
  type        = string
  default     = "55.5.0"
}

variable "external_secrets_chart_version" {
  description = "Version of the External Secrets Operator Helm chart to install."
  type        = string
  default     = "0.9.19"
}

variable "kyverno_chart_version" {
  description = "Version of the Kyverno Helm chart to install."
  type        = string
  default     = "3.2.6"
}

variable "velero_chart_version" {
  description = "Version of the Velero Helm chart to install."
  type        = string
  default     = "7.1.2"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket used by the Terraform remote backend (see backend.tf). Must be created once before `terraform init`; the backend block uses this name as a literal."
  type        = string
  default     = "eks-gitops-blueprint-tfstate"
}

variable "state_lock_table" {
  description = "Name of the DynamoDB table used for Terraform state locking (see backend.tf). Must be created once before `terraform init`."
  type        = string
  default     = "eks-gitops-blueprint-locks"
}
