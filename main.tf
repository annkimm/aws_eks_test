# Terraform 초기구성
terraform {
  backend "s3" {
    bucket         = "myterraform-bucket-state-kmg-t"
    key            = "aws_eks/terraform.tfstate"
    region         = "ap-northeast-2"
    profile        = "admin_user"
    dynamodb_table = "myTerraform-bucket-lock-kmg-t"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "ap-northeast-2"
  profile = "admin_user"
}

# AWS EKS Cluster
data "aws_iam_user" "EKS_Admin_ID" {
  user_name = "admin"
}

module "aws_eks_cluster" {
  source           = "./modules/eks_cluster"
  cidr             = "192.168.0.0/16"
  public_subnets   = ["192.168.1.0/24", "192.168.2.0/24"]
  private_subnets  = ["192.168.10.0/24", "192.168.20.0/24"]
  database_subnets = ["192.168.30.0/24", "192.168.40.0/24"]
  cluster_name     = "my-eks"
  cluster_version  = "1.30" // 1.3 이상 써야 돈이 많이 안나온데...
  cluster_admin    = data.aws_iam_user.EKS_Admin_ID.user_id // aws_auth를 자동으로 구성해줘서 지금은 없어도 괜찮음
}

output "vpc_id" {
  value       = module.aws_eks_cluster.vpc_id
  description = "VPC ID Output"
}

output "private_subnets" {
  value       = module.aws_eks_cluster.private_subnets_cidr_blocks
  description = "Private_Subnets_Cidr_Blocks Output"
}

output "database_subnets" {
  value       = module.aws_eks_cluster.database_subnets
  description = "Database_Subnets Output"
}

output "database_subnet_group" {
  value       = module.aws_eks_cluster.database_subnet_group
  description = "Database_Subnet_Group Output"
}

output "bastionhost_ip" {
  value       = module.aws_eks_cluster.bastionhost_ip
  description = "BastionHost IP Address Output"
}

# AWS RDS ( CI/CD에서 사용 예정 ) 

/* module "aws_eks_rds" {
  source      = "./modules/rds"
  db_port     = 3306
  db_name     = "django_db"
  db_username = "admin"
  db_password = "RDSterraform123!"
}

output "rds_instance_address" {
  value       = module.aws_eks_rds.rds_instance_address
  description = "DataBase Instance address"
}

module "ecr" {
  source                            = "terraform-aws-modules/ecr/aws"
  repository_name                   = "django"
  repository_read_write_access_arns = [data.aws_iam_user.EKS_Admin_ID.arn]
  create_lifecycle_policy           = false
  repository_image_scan_on_push     = false
  tags = {
    Terraform = "true"
  }
} */