# -----------------------------------------------------------------------------
# EKS GitOps Blueprint — security: External Secrets Operator + Kyverno
# Author: Nour El Houda Bouajila (https://github.com/nourhb)
#
# External Secrets Operator (ESO) syncs secrets from AWS Secrets Manager into
# Kubernetes Secrets — no secrets in git, no manual `kubectl create secret`.
# Its service account assumes an IRSA role scoped to this project's secrets.
#
# Kyverno enforces admission policies so insecure workloads are rejected at
# deploy time: containers must run as non-root, images may not use :latest,
# and every container must declare CPU/memory requests and limits.
# Policies run in Audit mode by default; switch validationFailureAction to
# Enforce once you have verified they do not break your add-ons.
# -----------------------------------------------------------------------------

# --- IAM: ESO controller role (IRSA, scoped to project secrets) ----------------

resource "aws_iam_role" "external_secrets" {
  name = "${local.name_prefix}-external-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.cluster.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub" = "system:serviceaccount:external-secrets:external-secrets"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_policy" "external_secrets" {
  name        = "${local.name_prefix}-external-secrets-policy"
  description = "Read-only access to this project's AWS Secrets Manager secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecrets",
      ]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${local.name_prefix}/*"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}

data "aws_caller_identity" "current" {}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_secrets.arn
  }

  depends_on = [aws_eks_node_group.default]
}

# --- Kyverno: policy engine -----------------------------------------------------

resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno/"
  chart            = "kyverno"
  version          = var.kyverno_chart_version
  namespace        = "kyverno"
  create_namespace = true

  set {
    name  = "admissionController.replicas"
    value = "1"
  }

  set {
    name  = "backgroundController.replicas"
    value = "1"
  }

  depends_on = [aws_eks_node_group.default]
}

# --- ClusterPolicy 1: containers must run as non-root ---------------------------

resource "kubernetes_manifest" "kyverno_require_non_root" {
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "require-run-as-non-root"
      annotations = {
        "policies.kyverno.io/title"       = "Require runAsNonRoot"
        "policies.kyverno.io/description" = "Running containers as root is forbidden; every container must set securityContext.runAsNonRoot=true."
      }
    }
    spec = {
      validationFailureAction = "Audit"
      background              = true
      rules = [{
        name = "require-run-as-non-root"
        match = {
          any = [{ resources = { kinds = ["Pod"] } }]
        }
        validate = {
          message = "Containers must set securityContext.runAsNonRoot=true."
          foreach = [{
            list = "request.object.spec.containers"
            deny = {
              conditions = {
                any = [{
                  key      = "{{ element.securityContext.runAsNonRoot || '' }}"
                  operator = "NotEquals"
                  value    = true
                }]
              }
            }
          }]
        }
      }]
    }
  }

  depends_on = [helm_release.kyverno]
}

# --- ClusterPolicy 2: images may not use the :latest tag ------------------------

resource "kubernetes_manifest" "kyverno_disallow_latest" {
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "disallow-latest-tag"
      annotations = {
        "policies.kyverno.io/title"       = "Disallow Latest Tag"
        "policies.kyverno.io/description" = "Images tagged :latest are not reproducible and are forbidden."
      }
    }
    spec = {
      validationFailureAction = "Audit"
      background              = true
      rules = [{
        name = "disallow-latest-tag"
        match = {
          any = [{ resources = { kinds = ["Pod"] } }]
        }
        validate = {
          message = "Using the :latest image tag is not allowed; pin an immutable tag instead."
          foreach = [{
            list = "request.object.spec.containers"
            deny = {
              conditions = {
                any = [
                  {
                    key      = "{{ element.image }}"
                    operator = "Equals"
                    value    = "*:latest"
                  },
                  {
                    key      = "{{ element.image }}"
                    operator = "NotContains"
                    value    = ":"
                  },
                ]
              }
            }
          }]
        }
      }]
    }
  }

  depends_on = [helm_release.kyverno]
}

# --- ClusterPolicy 3: every container must declare resource limits --------------

resource "kubernetes_manifest" "kyverno_require_limits" {
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "require-resource-limits"
      annotations = {
        "policies.kyverno.io/title"       = "Require Resource Limits"
        "policies.kyverno.io/description" = "Every container must declare CPU/memory requests and limits so the scheduler and Karpenter can bin-pack correctly."
      }
    }
    spec = {
      validationFailureAction = "Audit"
      background              = true
      rules = [{
        name = "require-resource-limits"
        match = {
          any = [{ resources = { kinds = ["Pod"] } }]
        }
        validate = {
          message = "CPU and memory requests and limits are required for every container."
          foreach = [{
            list = "request.object.spec.containers"
            deny = {
              conditions = {
                any = [
                  {
                    key      = "{{ request.object.spec.containers[{{ elementIndex }}].resources.requests.memory || '' }}"
                    operator = "Equals"
                    value    = ""
                  },
                  {
                    key      = "{{ request.object.spec.containers[{{ elementIndex }}].resources.limits.memory || '' }}"
                    operator = "Equals"
                    value    = ""
                  },
                ]
              }
            }
          }]
        }
      }]
    }
  }

  depends_on = [helm_release.kyverno]
}
