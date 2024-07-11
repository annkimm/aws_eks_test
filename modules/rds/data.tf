data "terraform_remote_state" "vpc_remote_data" {
  backend = "s3"
  config = {
    bucket  = "myterraform-bucket-state-kmg-t"
    key     = "aws_eks/terraform.tfstate"
    profile = "admin_user"
    region  = "ap-northeast-2"
  }
}