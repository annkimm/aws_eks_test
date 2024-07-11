
locals {
  tcp_protocol = "tcp"
  any_port     = 0
  any_protocol = "-1"
  all_network  = "0.0.0.0/0"
}

variable "db_port" {
  description = "RDS DB Port"
  type        = string
}

variable "db_name" {
  description = "RDS DB Name"
  type        = string
}

variable "db_username" {
  description = "RDS DB UserName"
  type        = string
}

variable "db_password" {
  description = "RDS DB Password"
  type        = string
}