output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "VPC ID Output"
}

output "private_subnets_cidr_blocks" {
  value       = module.vpc.private_subnets_cidr_blocks
  description = "Private_Subnets_Cidr_Blocks Output"
}

output "database_subnets" {
  value       = module.vpc.database_subnets
  description = "Database_Subnets Output"
}

output "database_subnet_group" {
  value       = module.vpc.database_subnet_group
  description = "Database_Subnet_Group Output"
}

output "bastionhost_ip" {
  value       = aws_eip.BastionHost_eip.public_ip
  description = "BastionHost IP Address Output"
}