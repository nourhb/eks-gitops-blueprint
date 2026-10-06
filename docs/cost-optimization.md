# Cost optimization

The default deployment costs roughly **$260–280/month** in `ca-central-1`
(see `terraform/README.md`). This page explains the levers that push the
real bill below that — and what each one trades off.

## 1. Karpenter with Spot-first provisioning

The biggest lever. Instead of a fixed managed node group sized for peak,
Karpenter (`terraform/karpenter.tf`):

- launches **right-sized nodes just-in-time** when pods are unschedulable,
  instead of keeping headroom warm 24/7;
- prefers **Spot instances** (`karpenter.sh/capacity-type: spot,
  on-demand` in the NodePool) — typically 60–70% cheaper than on-demand —
  with automatic fallback to on-demand when Spot is unavailable;
- **consolidates** under-utilized nodes after 30s (`WhenEmptyOrUnderutilized`),
  continuously re-packing the cluster;
- rotates nodes every 30 days (`expireAfter: 720h`) so you always run on
  fresh AMIs.

The Spot interruption queue (SQS + EventBridge) drains nodes gracefully
before reclaim, so Spot is safe for stateless workloads like the demo app.

## 2. Single NAT gateway

`single_nat_gateway = true` (default) shares one NAT gateway across AZs
instead of three. Saves ~$90/month. Trade-off: cross-AZ data charges and a
single point of failure — acceptable for dev/demo, flip to `false` for
production.

## 3. gp3 everywhere

A `gp3` StorageClass (`terraform/monitoring.tf`) backs Prometheus (50Gi)
and Grafana (10Gi). gp3 is ~20% cheaper than gp2 at the same performance
and lets you tune IOPS independently.

## 4. HPA + PodDisruptionBudget

The demo app's HPA (`kubernetes/hpa.yaml`) scales 2–6 replicas on CPU, so
idle periods run at the minimum. The PDB (`minAvailable: 1`) is what makes
Karpenter consolidation safe: nodes can be drained without ever taking the
app to zero.

## 5. Scale-to-zero when idle

Cheapest experiment mode: the cluster costs ~$110/month for the control
plane alone.

```bash
# Park the managed node group (Karpenter-created nodes drain via consolidation)
terraform -chdir=terraform apply -var='node_desired_size=0'
```

Argo CD keeps the desired state in git; scaling back up is one apply away.

## 6. Lifecycle hygiene

- ECR lifecycle policy keeps only the last 20 tagged images
  (`terraform/addons.tf`).
- Velero backups expire after 7 days (`ttl: 168h`).
- Prometheus retention is 15 days, not the chart's 90-day default.

## 7. What NOT to cheap out on

- Keep the DynamoDB-backed state lock and versioned tfstate bucket —
  state corruption costs more than the pennies they run.
- Keep control-plane logging (`api`, `audit`, `authenticator`) on; it is
  the cheapest incident-response tool you have.
- Keep Trivy/Checkov/tfsec in CI — a breached cluster dwarfs any
  infrastructure saving.
