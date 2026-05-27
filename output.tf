output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.custom_vpc.id
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = aws_subnet.public_subnets[*].id
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets"
  value       = aws_subnet.private_subnets[*].id
}

output "nat_gateway_ips" {
  description = "The public IP addresses of the NAT Gateways"
  value       = aws_eip.elastic_ip[*].public_ip
}

# 
/*
output "eks_connect_command" {
  description = "Command to configure kubectl to connect to the EKS cluster"
  value       = "aws eks --region ap-southeast-1 update-kubeconfig --name ${var.cluster_name}"
}*/