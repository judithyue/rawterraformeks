################################################################################
# 1. NETWORKING (VPC & SUBNETS)
################################################################################

resource "aws_vpc" "custom_vpc" {
  cidr_block = var.networking.cidr_block

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-VPC"
  })
}

resource "aws_subnet" "public_subnets" {
  count                   = length(var.networking.public_subnets)
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = var.networking.public_subnets[count.index]
  availability_zone       = var.networking.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name                                               = "${var.naming_prefix}-public-subnet-${count.index}"
    "kubernetes.io/role/elb"                           = "1"
    "kubernetes.io/cluster/${var.cluster_config.name}" = "shared"
  })
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.networking.private_subnets)
  vpc_id            = aws_vpc.custom_vpc.id
  cidr_block        = var.networking.private_subnets[count.index]
  availability_zone = var.networking.azs[count.index]

  tags = merge(var.common_tags, {
    Name                                               = "${var.naming_prefix}-private-subnet-${count.index}"
    "kubernetes.io/role/internal-elb"                  = "1"
    "kubernetes.io/cluster/${var.cluster_config.name}" = "shared"
  })
}

################################################################################
# 2. GATEWAYS & ROUTING
################################################################################

resource "aws_internet_gateway" "i_gateway" {
  vpc_id = aws_vpc.custom_vpc.id
  tags   = merge(var.common_tags, { Name = "${var.naming_prefix}-igw" })
}

resource "aws_eip" "elastic_ip" {
  count      = var.networking.nat_gateways ? length(var.networking.public_subnets) : 0
  depends_on = [aws_internet_gateway.i_gateway]

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-eip-${count.index}"
  })
}

resource "aws_nat_gateway" "nats" {
  count         = var.networking.nat_gateways ? length(var.networking.public_subnets) : 0
  subnet_id     = aws_subnet.public_subnets[count.index].id
  allocation_id = aws_eip.elastic_ip[count.index].id
  tags          = merge(var.common_tags, { Name = "${var.naming_prefix}-nat-${count.index}" })
}

resource "aws_route_table" "public_table" {
  vpc_id = aws_vpc.custom_vpc.id

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-public-route-table"
  })
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.i_gateway.id
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_table.id
}

resource "aws_route_table" "private_tables" {
  count  = length(var.networking.private_subnets)
  vpc_id = aws_vpc.custom_vpc.id

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-private-route-table-${count.index}"
  })
}

resource "aws_route" "private_nat_access" {
  count                  = var.networking.nat_gateways ? length(var.networking.private_subnets) : 0
  route_table_id         = aws_route_table.private_tables[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nats[count.index].id
}

resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_tables[count.index].id
}

################################################################################
# 3. SECURITY GROUPS (The "DRY" Factory)
################################################################################

resource "aws_security_group" "sec_groups" {
  for_each    = { for sec in var.security_groups : sec.name => sec }
  name        = "${var.naming_prefix}-${each.value.name}"
  description = each.value.description
  vpc_id      = aws_vpc.custom_vpc.id

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-${each.value.name}-sg"
  })

  dynamic "ingress" {
    for_each = each.value.ingress
    content {
      description = ingress.value.description
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  dynamic "egress" {
    for_each = each.value.egress
    content {
      description = egress.value.description
      from_port   = egress.value.from_port
      to_port     = egress.value.to_port
      protocol    = egress.value.protocol
      cidr_blocks = egress.value.cidr_blocks
    }
  }
}

################################################################################
# 4. IAM ROLES (EKS & NODES)
################################################################################

resource "aws_iam_role" "EKSClusterRole" {
  name = "${var.naming_prefix}-EKSClusterRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "eks.amazonaws.com" } }]
  })

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-EKSClusterRole"
  })
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.EKSClusterRole.name
}

resource "aws_iam_role" "NodeGroupRole" {
  name = "${var.naming_prefix}-EKSNodeGroupRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-EKSNodeGroupRole"
  })
}

resource "aws_iam_role_policy_attachment" "node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  ])
  policy_arn = each.value
  role       = aws_iam_role.NodeGroupRole.name
}

################################################################################
# 5. EKS CLUSTER & NODE GROUPS
################################################################################

resource "aws_eks_cluster" "eks-cluster" {
  name     = var.cluster_config.name
  role_arn = aws_iam_role.EKSClusterRole.arn
  version  = var.cluster_config.version

  tags = merge(var.common_tags, {
    Name = var.cluster_config.name
  })

  vpc_config {
    # DIRECT REFERENCE to your Subnets and Sec Groups
    subnet_ids         = flatten([aws_subnet.public_subnets[*].id, aws_subnet.private_subnets[*].id])
    security_group_ids = [for sg in aws_security_group.sec_groups : sg.id]
  }

  depends_on = [aws_iam_role_policy_attachment.AmazonEKSClusterPolicy]
}

resource "aws_eks_node_group" "node-ec2" {
  for_each        = { for node_group in var.node_groups : node_group.name => node_group }
  cluster_name    = aws_eks_cluster.eks-cluster.name
  node_group_name = "${var.naming_prefix}-${each.value.name}"
  node_role_arn   = aws_iam_role.NodeGroupRole.arn
  subnet_ids      = aws_subnet.private_subnets[*].id

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-${each.value.name}-nodegroup"
  })

  scaling_config {
    desired_size = each.value.scaling_config.desired_size
    max_size     = each.value.scaling_config.max_size
    min_size     = each.value.scaling_config.min_size
  }

  ami_type       = each.value.ami_type
  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type
  disk_size      = each.value.disk_size

  depends_on = [aws_iam_role_policy_attachment.node_policies]
}

################################################################################
# 6. ADDONS & OIDC
################################################################################

resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  url             = aws_eks_cluster.eks-cluster.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-eks-oidc-provider"
  })
}

resource "aws_eks_addon" "addons" {
  for_each                    = var.addons
  cluster_name                = aws_eks_cluster.eks-cluster.name
  addon_name                  = each.value.name
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [aws_eks_node_group.node-ec2]
}

################################################################################
# 7. ECR
################################################################################
resource "aws_ecr_repo" "ecr" {
  repo_name = var.ecr_config.repo_name
  image_tag_mutability = var.ecr_config.image_tag_mutability
  force_delete = var.ecr_config.force_delete

image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-ecr-repo"
  })
}
