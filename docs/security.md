# Security — defense in depth

This blueprint layers independent controls so no single misconfiguration
hands an attacker the cluster. Each layer below is implemented in the repo,
not just recommended.

## 1. Identity: short-lived credentials everywhere

| Surface | Mechanism | Where |
|---|---|---|
| CI → AWS | GitHub OIDC federation; the `AWS_ROLE_ARN` role is assumed per-run, no static keys | `.github/workflows/*.yaml` |
| Pods → AWS | IRSA: per-service-account IAM roles (EBS CSI, ALB controller, Karpenter, ESO, Velero) | `terraform/eks.tf`, `addons.tf`, `karpenter.tf`, `security.tf`, `velero.tf` |
| Humans → cluster | `aws eks update-kubeconfig` (STS-backed tokens), private API endpoint enabled | `terraform/eks.tf` |

Node instance profiles carry only the worker-node policies — application
permissions always come from IRSA, never from the node role.

## 2. Admission control: Kyverno

Three `ClusterPolicy` resources (`terraform/security.tf`) evaluate every Pod
at admission time and continuously in the background:

- **require-run-as-non-root** — containers must set `runAsNonRoot: true`.
- **disallow-latest-tag** — `:latest` (and untagged) images are rejected;
  only immutable, traceable tags are deployable.
- **require-resource-limits** — every container must declare CPU/memory
  requests and limits, so the scheduler and Karpenter can bin-pack safely.

They ship in `Audit` mode: violations are reported, not blocked. Flip
`validationFailureAction` to `Enforce` once you have confirmed the platform
charts comply.

## 3. Network segmentation

- Nodes live in **private subnets**; the only internet-facing component is
  the ALB (`terraform/vpc.tf`, `terraform/eks.tf`).
- `kubernetes/networkpolicy.yaml` applies **default-deny** ingress/egress
  in the `demo-app` namespace, then allows only DNS (CoreDNS) egress and
  ingress to the app port. The VPC CNI enforces these natively.

## 4. Workload hardening

The demo app (`kubernetes/deployment.yaml`, `app/Dockerfile`) is the
reference for how workloads should look:

- Distroless runtime image, **non-root user (65532)**, read-only root
  filesystem, all Linux capabilities dropped, seccomp `RuntimeDefault`.
- Liveness/readiness probes, resource requests + limits (required by the
  Kyverno policy above), `PodDisruptionBudget` (`minAvailable: 1`).

## 5. Supply chain

- ECR repositories use **immutable tags** and **scan-on-push**.
- CI fails the build on Trivy `CRITICAL`/`HIGH` findings and lints the
  Dockerfile with Hadolint (`.github/workflows/ci.yaml`).
- Checkov + tfsec scan `terraform/` on every PR; `terraform plan` output is
  posted as a PR comment before anything can be applied
  (`.github/workflows/terraform.yaml`).

## 6. Secrets management

No secrets in git, ever. The External Secrets Operator syncs from AWS
Secrets Manager into Kubernetes Secrets (`kubernetes/externalsecret.yaml`);
the controller's IRSA role can only read secrets under
`blueprint-dev/*` (`terraform/security.tf`).

## 7. Backup and recovery

Velero takes a **daily backup** of the `demo-app` and `monitoring`
namespaces (7-day retention) to an encrypted, versioned S3 bucket
(`terraform/velero.tf`). Run restore drills with:

```bash
velero backup create manual-drill --include-namespaces demo-app
velero backup describe manual-drill
```

## 8. Progressive delivery

`kubernetes/rollout.yaml` is an Argo Rollouts canary (20% → pause →
50% → pause → 100%) that can replace the plain Deployment for
risk-sensitive releases. Combined with the PDB and probes, a bad release
is contained to a fraction of traffic and never takes the app fully down.
