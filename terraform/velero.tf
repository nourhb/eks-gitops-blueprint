# -----------------------------------------------------------------------------
# EKS GitOps Blueprint — Velero: cluster backup and disaster recovery
# Author: Nour El Houda Bouajila (https://github.com/nourhb)
#
# Velero backs up Kubernetes resources and persistent volumes to an S3
# bucket on a daily schedule (7-day retention). The Velero server runs with
# an IRSA role scoped to the backup bucket — no static credentials.
#
# Restore drill:
#   velero backup create manual-drill --include-namespaces demo-app
#   velero backup describe manual-drill
# -----------------------------------------------------------------------------

# --- S3 bucket for backups -------------------------------------------------------

resource "aws_s3_bucket" "velero" {
  bucket = "${local.name_prefix}-velero-backups"

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "velero" {
  bucket = aws_s3_bucket.velero.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket = aws_s3_bucket.velero.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- IAM: Velero server role (IRSA) ----------------------------------------------

resource "aws_iam_role" "velero" {
  name = "${local.name_prefix}-velero-server"

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
          "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub" = "system:serviceaccount:velero:velero"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_policy" "velero" {
  name        = "${local.name_prefix}-velero-server-policy"
  description = "S3/EC2 permissions for Velero backups and restores"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = [
          aws_s3_bucket.velero.arn,
          "${aws_s3_bucket.velero.arn}/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot",
          "ec2:CreateTags",
          "ec2:DescribeTags",
        ]
        Resource = "*"
      },
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "velero" {
  role       = aws_iam_role.velero.name
  policy_arn = aws_iam_policy.velero.arn
}

# --- Velero (Helm) ----------------------------------------------------------------

resource "helm_release" "velero" {
  name             = "velero"
  repository       = "https://vmware-tanzu.github.io/helm-charts"
  chart            = "velero"
  version          = var.velero_chart_version
  namespace        = "velero"
  create_namespace = true

  set {
    name  = "serviceAccount.server.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.velero.arn
  }

  set {
    name  = "configuration.provider"
    value = "aws"
  }

  set {
    name  = "configuration.backupStorageLocation[0].name"
    value = "default"
  }

  set {
    name  = "configuration.backupStorageLocation[0].provider"
    value = "aws"
  }

  set {
    name  = "configuration.backupStorageLocation[0].bucket"
    value = aws_s3_bucket.velero.id
  }

  set {
    name  = "configuration.backupStorageLocation[0].config.region"
    value = var.aws_region
  }

  set {
    name  = "configuration.volumeSnapshotLocation[0].name"
    value = "default"
  }

  set {
    name  = "configuration.volumeSnapshotLocation[0].provider"
    value = "aws"
  }

  set {
    name  = "configuration.volumeSnapshotLocation[0].config.region"
    value = var.aws_region
  }

  # AWS plugin matching Velero 1.15.
  set {
    name  = "initContainers[0].name"
    value = "velero-plugin-for-aws"
  }

  set {
    name  = "initContainers[0].image"
    value = "velero/velero-plugin-for-aws:v1.10.0"
  }

  set {
    name  = "initContainers[0].volumeMounts[0].mountPath"
    value = "/target"
  }

  set {
    name  = "initContainers[0].volumeMounts[0].name"
    value = "plugins"
  }

  depends_on = [aws_eks_node_group.default]
}

# --- Daily backup schedule (namespaces + 7-day retention) -------------------------

resource "kubernetes_manifest" "velero_daily_schedule" {
  manifest = {
    apiVersion = "velero.io/v1"
    kind       = "Schedule"
    metadata = {
      name      = "daily-cluster-backup"
      namespace = "velero"
    }
    spec = {
      schedule = "0 2 * * *" # 02:00 UTC daily
      template = {
        includedNamespaces = ["demo-app", "monitoring"]
        ttl                = "168h" # 7 days
        storageLocation    = "default"
        volumeSnapshotLocations = ["default"]
      }
    }
  }

  depends_on = [helm_release.velero]
}
