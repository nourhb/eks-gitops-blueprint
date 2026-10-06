# Terraform

This directory provisions the full AWS foundation: VPC, EKS cluster, IAM roles
(IRSA), EBS CSI driver, AWS Load Balancer Controller, Argo CD, Karpenter node
autoscaling, kube-prometheus-stack monitoring, External Secrets Operator,
Kyverno admission policies, Velero backups, and the ECR repository for the
demo application.

State is stored remotely: S3 backend with DynamoDB locking (`backend.tf`).
Run the one-time bootstrap documented in `backend.tf` before `terraform init`.

## Cost estimate (ca-central-1, defaults, prices as of 2026)

| Resource                        | Approx. monthly cost |
|---------------------------------|----------------------|
| EKS control plane               | ~$110                |
| 2 × t3.medium worker nodes      | ~$70                 |
| 1 × NAT gateway + data transfer | ~$45–60              |
| EBS volumes (gp3, ~70 GB)       | ~$8                  |
| ALB (when Ingress is created)   | ~$25 + LCU charges   |
| ECR storage                     | <$1                  |
| SQS (Karpenter interruption)    | <$1                  |
| S3 (Velero backups + tfstate)   | ~$1–3                |
| DynamoDB (state locking)        | <$1                  |
| **Total**                       | **~$260–280 / month**|

Notes: Karpenter consolidates idle nodes and prefers Spot, so a real
steady-state bill is usually *below* this estimate. Prometheus/Grafana/Velero
run on the existing nodes — no extra EC2 cost beyond their EBS volumes.

Cheapest way to experiment: keep the cluster up only while testing, or set
`node_desired_size = 0` when idle (the control-plane charge remains).

## Deploy

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # adjust if needed
terraform init
terraform plan -out plan.tfplan
terraform apply plan.tfplan
```

Configure kubectl afterwards:

```bash
aws eks update-kubeconfig --region ca-central-1 --name blueprint-eks
```

## Cleanup

Destroy everything to stop all charges:

```bash
terraform destroy
```

Destroy in this order if you prefer manual control:

1. Delete the Argo CD `Application` and any `Ingress` objects first so the ALB
   and its target groups are removed by the controller.
2. `terraform destroy -target=helm_release.argocd -target=helm_release.alb_controller`
3. `terraform destroy` for the remainder.
