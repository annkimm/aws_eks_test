locals {
  region           = "ap-northeast-2"
  azs              = ["ap-northeast-2a", "ap-northeast-2c"]
  cidr             = var.cidr
  public_subnets   = var.public_subnets
  private_subnets  = var.private_subnets
  database_subnets = var.database_subnets
  ssh_port         = 22
  any_port         = 0
  any_protocol     = "-1"
  tcp_protocol     = "tcp"
  icmp_protocol    = "icmp"
  all_network      = "0.0.0.0/0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  cluster_admin   = var.cluster_admin
  tags = {
    cluster_name = var.cluster_name
  }
}

variable "cidr" {
  description = "VPC CIDR BLOCK"
  type        = string
}

variable "public_subnets" {
  description = "VPC Public Subnets"
  type        = list(any)
}

variable "private_subnets" {
  description = "VPC Private Subnets"
  type        = list(any)
}

variable "database_subnets" {
  description = "VPC Database Subnets"
  type        = list(any)
}

variable "cluster_name" {
  description = "EKS Cluster Name"
  type        = string
}

variable "cluster_version" {
  description = "EKS Cluster Version"
  type        = string
}

variable "cluster_admin" {
  description = "Cluster Admin IAM User Account ID"
  type        = string
}