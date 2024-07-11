
# =================================================================================================
# =================================================================================================
# =================================================================================================

# VPC
module "vpc" {
  source           = "terraform-aws-modules/vpc/aws"
  version          = "5.1.1"
  name             = "eks_vpc"
  azs              = local.azs
  cidr             = local.cidr
  public_subnets   = local.public_subnets
  private_subnets  = local.private_subnets
  database_subnets = local.database_subnets

  enable_dns_hostnames = "true"
  enable_dns_support   = "true"
  tags = {
    "TerraformManaged" = "true"
  }
}

# Security-Group (BastionHost)
module "BastionHost_SG" {
  source          = "terraform-aws-modules/security-group/aws"
  version         = "5.1.0"
  name            = "BastionHost_SG"
  description     = "BastionHost_SG"
  vpc_id          = module.vpc.vpc_id
  use_name_prefix = "false"

  ingress_with_cidr_blocks = [
    {
      from_port   = local.ssh_port
      to_port     = local.ssh_port
      protocol    = local.tcp_protocol
      description = "SSH"
      cidr_blocks = local.all_network
    },
    {
      from_port   = local.any_protocol
      to_port     = local.any_protocol
      protocol    = local.icmp_protocol
      description = "ICMP"
      cidr_blocks = local.cidr
    }
  ]
  egress_with_cidr_blocks = [
    {
      from_port   = local.any_port
      to_port     = local.any_port
      protocol    = local.any_protocol
      cidr_blocks = local.all_network
    }
  ]
}

# BastionHost EIP
resource "aws_eip" "BastionHost_eip" {
  instance = aws_instance.BastionHost.id
  tags = {
    Name = "BastionHost_EIP"
  }
}

# BastionHost Key-Pair DataSource
data "aws_key_pair" "EC2-Key" {
  key_name = "EC2-key"
}

# BastionHost Instance
# EKS Cluster SG : data.aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id 
# EKS Cluster SG : 보안그룹을 설정함으로써 Bastion host <-> EKS 간의 트래픽을 허용해줄 수 있는 형태로 만들어줄 수 있음
resource "aws_instance" "BastionHost" {
  ami                         = "ami-0ea4d4b8dc1e46212"
  instance_type               = "t2.micro"
  key_name                    = data.aws_key_pair.EC2-Key.key_name
  subnet_id                   = module.vpc.public_subnets[1]
  associate_public_ip_address = true
  vpc_security_group_ids      = [module.BastionHost_SG.security_group_id, data.aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id]
  depends_on                  = [module.eks]
  tags = {
    Name = "BastionHost_Instance"
  }
}

# Security-Group (NAT-Instance)
module "NAT_SG" {
  source          = "terraform-aws-modules/security-group/aws"
  version         = "5.1.0"
  name            = "NAT_SG"
  description     = "All Traffic"
  vpc_id          = module.vpc.vpc_id
  use_name_prefix = "false"

  ingress_with_cidr_blocks = [
    {
      from_port   = local.any_port
      to_port     = local.any_port
      protocol    = local.any_protocol
      cidr_blocks = local.private_subnets[0]
    },
    {
      from_port   = local.any_port
      to_port     = local.any_port
      protocol    = local.any_protocol
      cidr_blocks = local.private_subnets[1]
    }
  ]
  egress_with_cidr_blocks = [
    {
      from_port   = local.any_port
      to_port     = local.any_port
      protocol    = local.any_protocol
      cidr_blocks = local.all_network
    }
  ]
}

# NAT Instance ENI(Elastic Network Interface)
resource "aws_network_interface" "NAT_ENI" {
  subnet_id         = module.vpc.public_subnets[0]
  private_ips       = ["192.168.1.50"]
  security_groups   = [module.NAT_SG.security_group_id]
  source_dest_check = false

  tags = {
    Name = "NAT_Instance_ENI"
  }
}

# NAT Instance 
resource "aws_instance" "NAT_Instance" {
  ami           = "ami-00295862c013bede0"
  instance_type = "t2.micro"
  depends_on    = [aws_network_interface.NAT_ENI]

  network_interface {
    network_interface_id = aws_network_interface.NAT_ENI.id
    device_index         = 0
  }

  tags = {
    Name = "NAT_Instance"
  }
}

# NAT Instance ENI EIP
resource "aws_eip" "NAT_Instance_eip" {
  network_interface = aws_network_interface.NAT_ENI.id
  tags = {
    Name = "NAT_EIP"
  }
  depends_on = [aws_network_interface.NAT_ENI, aws_instance.NAT_Instance]
}

# Private Subnet Routing Table ( dest: NAT Instance ENI )
# 우선순위가 data가 먼저 실행되는 경우가 훨씬 많아서 depends_on을 걸면 
# vpc 리소스가 먼저 실행되고 나면 그 뒤에 아래 코드가 실행된다.
data "aws_route_table" "private_1" {
  subnet_id  = module.vpc.private_subnets[0]
  depends_on = [module.vpc]
}

data "aws_route_table" "private_2" {
  subnet_id  = module.vpc.private_subnets[1]
  depends_on = [module.vpc]
}

resource "aws_route" "private_subnet_1" {
  route_table_id         = data.aws_route_table.private_1.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.NAT_ENI.id
  depends_on             = [module.vpc, aws_instance.NAT_Instance]
}

resource "aws_route" "private_subnet_2" {
  route_table_id         = data.aws_route_table.private_2.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.NAT_ENI.id
  depends_on             = [module.vpc, aws_instance.NAT_Instance]
}

# =================================================================================================
# =================================================================================================
# =================================================================================================

/* 
  # Kubernetes 추가 Provider
  EKS Cluster 구성 후 초기 구성 작업을 수행하기 위한 Terraform Kubernetes Provider 설정 
  생성 된 EKS Cluster의 EndPoint 주소 및 인증정보등을 DataSource로 정의 후 Provider 설정 정보로 입력
 */

# AWS EKS Cluster Data Source
data "aws_eks_cluster" "cluster" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

# AWS EKS Cluster Auth Data Source
data "aws_eks_cluster_auth" "cluster" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

# AWS EKS Cluster DataSource DOCS 
# - aws_eks_cluster      : https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_cluster.html
# - aws_eks_cluster_auth : https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_cluster_auth

# 테라폼에서 쿠버네티스 또한 쓰겠다고 등록이 가능함 -> 쿠버네티스의 명령어 또한 가져올 수 있음
# 관리자 등록하는 게 하도 어렵다고 말이 나와서 aws에서 새로운 옵션이 나옴 -> enable_cluster_creator_admin_permissions 옵션
# route 53과 같은 서비스와 연동하는 작업을 하려고 할 때 수동으로 통합 셋팅으로 하지만, 한번에 자동으로 생성할 수 있도록 하게 할 때
# 쿠버네티스 폴더만 따로 빼서 쓰기도 함.
# 테라폼 코드 가지고 실제로 쿠버네티스 명령어를 실행하기도 함
# 이게 제일 어려운 부분!
provider "kubernetes" {
  # 어떤 클러스터에서 사용할건지 -> 만들어진 클러스터의 접속할 수 있는 endpoint 주소값을 명시 -> 내가 작업할 클러스터의 정보
  host                   = data.aws_eks_cluster.cluster.endpoint
  # cluster_ca_certificate: CA 인증서
  # 어떤 통신 -> 명령어 전달 등의 모든 작업을 할 때 SSL 통신을 하게 되어 있음 평문이 아니라 모두 암호화 시켜서 전달하게 되어 있음
  # 아무거나 가져오는 게 아니라 클러스터의 내부에서 쓰는 인증서를 가져오는 것
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  # token: 인증값 (클러스터의 접근할 수 있는 인증값)
  # 인증값을 가지고 있는 녀석만 실제로 클러스터에 접근해서 작업을 할 수 있게 하는 것 
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# Terraform EKS Module DOCS : https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest
# 이건 걍 aws에서 모듈 불러와서 쓰라... 그게 맞다..일반적이다..
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"
  # 20버전 미만은 비용이 0.6 달러/ 20버전보다 높을 경우 0.1 달러

  # EKS Cluster Setting
  cluster_name    = local.cluster_name // 클러스터 이름
  cluster_version = local.cluster_version // 클러스터 버전
  vpc_id          = module.vpc.vpc_id // VPC Id
  subnet_ids      = module.vpc.private_subnets // 어떤 서브넷 사용할건지

  # OIDC(OpenID Connect) 구성
  # 클러스터 구성해놓고 내부 쿠버네티스 상에서 외부 리소스와 연결할 때 OIDC 값이 필요
  # 클러스터에게 부여할 OIDC를 자동으로 만들어주는 역할을 함
  # 이 값으로 클러스터를 식별한다고 보면 됨
  # 클러스터를 여러 개로 만들어서 사용해야 할 때 필요. 솔직히 하나의 클러스터라면 불필요
  enable_irsa = true

  # EKS Worker Node 정의 ( ManagedNode방식 / Launch Template 자동 구성 )
  # 완전 관리형 -> Launch Template까지 알아서 구성해줌
  # self 구성은 내가 auto scaling이랑 Launch Template까지 해서 구성해줘야함, 테스트도 많이 해야 하고, 이미지 공부도 많이 해야 함 
  # 인위적으로 AMI를 내가 선택할 수 없고, Launch Template를 업데이트하고 싶어서 업데이트를 할 수가 없음
  # 볼륨 같은 걸 제어하기가 힘듦. 세세한 커스텀마이징이 필요한 환경에서는 완전 관리형을 사용할 수가 없음
  # 금융권이나 보안이 중요한 곳에서 완전관리형을 사용하기가 힘듦
  # self로 너무 하기가 빡세서 AWS에서 만든게 카펜터인데 오픈 소스 형태로 제공해줌
  # 워크 노드들을 위한 프로비저닝을 카펜터로 할 수 있음
  # 완전관리형에서 커스터마이징을 하고 싶을 때 카펜터로 사용 가능 -> 부분적으로 카펜터 도입 테스트 (테라폼처럼 세세하게 설정 가능쓰...)
  # 노드 관리를 잘하면 이쁨 받는뎅...
  eks_managed_node_groups = {
    EKS_Worker_Node = {
      instance_types = ["t3.small"]
      # 아래의 지정된 값을 가지고 자동으로 auto scaling 생성
      min_size       = 2
      max_size       = 3
      desired_size   = 2
    }
  }

  # 외부와 통신하는 방법
  # 1. bastion host (원격 접속)에서 EKS에 구성되어 있는 클러스터 내부의 노드를 관리하는 형태로 운영가능
  # bastion host 원격 접속 -> EKS -> manifest.yml -> master node -> worker node
  # bastion host에서 무조건 접근할 수 있도록 만들면 보안이 좋아질 수 있음
  # 2. 로컬에서 EKS에 직접 명령을 내릴 수도 있는 형태로 운영가능
  # 로컬 -> EKS -> manifest.yml -> master node -> worker node
  # 외부에서 접근할 수 있도록 EKS에서 풀어줘야하기 때문에 보안이 좋지는 않음
  # public-subnet(bastion)과 API와 통신하기 위해 설정(443), 외부와의 통신을 위해서 무조건 풀어줘야함 bastion host든, lcoal이든
  cluster_endpoint_public_access = true

  # K8s ConfigMap Object "aws_auth" 구성
  # 관리자 정보가 들어있음. 이 클러스터를 관리하는 정보가 누군인지에 대해서 등록하는 것
  # 그렇게 했을 때 manifest.yml에서 받아들여서 master node에서 작업에 대해서 전달하는 것. 
  # 관리자가 아니라면 아무리 해봤자 block을 당함 -> IAM의 admin 유저에 대한 정보를 등록시켜줘야함
  # 그래서 IAM을 만들 때 권한으로 admin을 넣어준 것
  enable_cluster_creator_admin_permissions = true
}

// Private Subnet Tag ( AWS Load Balancer Controller Tag / internal )
resource "aws_ec2_tag" "private_subnet_tag" {
  for_each    = { for idx, subnet in module.vpc.private_subnets : idx => subnet }
  resource_id = each.value
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}

// Public Subnet Tag (AWS Load Balancer Controller Tag / internet-facing)
resource "aws_ec2_tag" "public_subnet_tag" {
  for_each    = { for idx, subnet in module.vpc.public_subnets : idx => subnet }
  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}
