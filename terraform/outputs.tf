# -----------------------------------------------------------------------------
# EKS GitOps Blueprint — outputs
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "Name of the provisioned EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "API endpoint of the EKS control plane."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster (used by IRSA and CI OIDC)."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets hosting the worker nodes."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets hosting load balancers."
  value       = aws_subnet.public[*].id
}

output "ecr_repository_url" {
  description = "URL of the ECR repository for the demo application image."
  value       = aws_ecr_repository.app.repository_url
}

output "argocd_namespace" {
  description = "Kubernetes namespace where Argo CD is installed."
  value       = "argocd"
}

output "kubeconfig_command" {
  description = "AWS CLI command to configure kubectl for this cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
}

output "grafana_admin_password" {
  description = "Generated Grafana admin password (user: admin). Marked sensitive."
  value       = random_password.grafana_admin.result
  sensitive   = true
}

output "grafana_port_forward_command" {
  description = "Command to access the Grafana UI locally."
  value       = "kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80"
}

output "velero_backup_bucket" {
  description = "Name of the S3 bucket storing Velero cluster backups."
  value       = aws_s3_bucket.velero.id
}

output "karpenter_nodepool" {
  description = "Karpenter NodePool/EC2NodeClass status note."
  value       = "Karpenter controller installed in namespace 'karpenter'; NodePool 'default' (Spot-first) and EC2NodeClass 'default' applied."
}

output "kyverno_policies" {
  description = "Kyverno ClusterPolicies installed (Audit mode)."
  value       = ["require-run-as-non-root", "disallow-latest-tag", "require-resource-limits"]
}
