# -----------------------------------------------------------------------------
# EKS GitOps Blueprint — Karpenter: intelligent node autoscaling
# Author: Nour El Houda Bouajila (https://github.com/nourhb)
#
# Karpenter replaces the Cluster Autoscaler with just-in-time provisioning:
# it launches right-sized nodes (including Spot) the moment an unschedulable
# pod appears, then consolidates under-utilized nodes away. Result: lower
# cost and faster scale-out than ASG-based autoscaling.
#
# Discovery: Karpenter finds subnets and security groups through the
# `karpenter.sh/discovery` tag applied below to the private subnets and the
# cluster security group.
# -----------------------------------------------------------------------------

# --- IAM: Karpenter controller role (IRSA) ------------------------------------

resource "aws_iam_role" "karpenter" {
  name = "${local.name_prefix}-karpenter-controller"

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
          "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub" = "system:serviceaccount:karpenter:karpenter"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_policy" "karpenter" {
  name        = "${local.name_prefix}-karpenter-controller-policy"
  description = "Permissions for the Karpenter controller to provision EC2 capacity"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Read"
        Effect = "Allow"
        Action = [
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeAvailabilityZones",
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2Provision"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateTags",
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate",
        ]
        Resource = "*"
      },
      {
        Sid      = "IAMPassRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.nodes.arn
      },
      {
        Sid    = "SSMRead"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
        ]
        Resource = "arn:aws:ssm:${var.aws_region}::parameter/aws/service/*"
      },
      {
        Sid    = "PricingRead"
        Effect = "Allow"
        Action = [
          "pricing:GetProducts",
        ]
        Resource = "*"
      },
      {
        Sid    = "InterruptionQueue"
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage",
        ]
        Resource = aws_sqs_queue.karpenter_interruption.arn
      },
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "karpenter" {
  role       = aws_iam_role.karpenter.name
  policy_arn = aws_iam_policy.karpenter.arn
}

# --- Interruption queue (Spot reclaim / rebalance handling) --------------------

resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${local.name_prefix}-karpenter-interruption"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = local.common_tags
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridge"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.karpenter_interruption.arn
    }]
  })
}

# --- Instance profile: Karpenter-provisioned nodes join with the node role ----

resource "aws_iam_instance_profile" "karpenter_nodes" {
  name = "${local.name_prefix}-karpenter-node-profile"
  role = aws_iam_role.nodes.name

  tags = local.common_tags
}

# --- Discovery tags (subnets + cluster security group) ------------------------

resource "aws_ec2_tag" "karpenter_private_subnets" {
  for_each    = toset(aws_subnet.private[*].id)
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = local.name_prefix
}

resource "aws_ec2_tag" "karpenter_cluster_sg" {
  resource_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = local.name_prefix
}

# --- Karpenter controller (Helm, OCI) ------------------------------------------

resource "helm_release" "karpenter" {
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_chart_version
  namespace        = "karpenter"
  create_namespace = true

  set {
    name  = "settings.clusterName"
    value = aws_eks_cluster.this.name
  }

  set {
    name  = "settings.interruptionQueue"
    value = aws_sqs_queue.karpenter_interruption.name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.karpenter.arn
  }

  set {
    name  = "controller.resources.requests.cpu"
    value = "500m"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "1Gi"
  }

  depends_on = [aws_eks_node_group.default]
}

# --- EC2NodeClass: what kind of nodes Karpenter may create ---------------------

resource "kubernetes_manifest" "karpenter_nodeclass" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      role = aws_iam_role.nodes.name
      amiFamily = "AL2023"
      subnetSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = local.name_prefix }
      }]
      securityGroupSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = local.name_prefix }
      }]
      blockDeviceMappings = [{
        deviceName = "/dev/xvda"
        ebs = {
          volumeSize          = "50Gi"
          volumeType          = "gp3"
          deleteOnTermination = true
        }
      }]
      tags = local.common_tags
    }
  }

  depends_on = [helm_release.karpenter]
}

# --- NodePool: Spot-first with on-demand fallback, aggressive consolidation ----

resource "kubernetes_manifest" "karpenter_nodepool" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "default"
    }
    spec = {
      template = {
        spec = {
          requirements = [
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
            { key = "kubernetes.io/os", operator = "In", values = ["linux"] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["spot", "on-demand"] },
            { key = "karpenter.k8s.aws/instance-category", operator = "In", values = ["c", "m", "r"] },
            { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = ["2"] },
          ]
          nodeClassRef = {
            group = "karpenter.sh"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          expireAfter = "720h" # 30 days: rotate nodes regularly for fresh AMIs
        }
      }
      limits = {
        cpu = "100"
      }
      # Consolidate under-utilized nodes after 30s of idleness.
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "30s"
      }
    }
  }

  depends_on = [kubernetes_manifest.karpenter_nodeclass]
}
