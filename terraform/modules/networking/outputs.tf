output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC"
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
  description = "IDs of private subnets"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "IDs of public subnets"
}

output "vpc_endpoint_sg_id" {
  value       = aws_security_group.vpc_endpoints.id
  description = "ID of security group governing VPC endpoints"
}

output "secretsmanager_endpoint_id" {
  value       = try(aws_vpc_endpoint.interface_endpoints["secretsmanager"].id, "")
  description = "ID of Secrets Manager VPC Endpoint"
}
