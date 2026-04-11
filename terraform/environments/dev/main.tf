data "aws_acm_certificate" "wildcard" {
  domain      = "*.alexanderkachar.com"
  statuses    = ["ISSUED"]
  most_recent = true
}

data "aws_elb_hosted_zone_id" "main" {}

locals {
  tags = {
    Project     = var.project_name
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source     = "../../modules/vpc"
  name       = "${var.project_name}-dev"
  cidr_block = "10.0.0.0/16"
}

module "ecr" {
  source = "../../modules/ecr"
  repository_names = [
    "todo-app-frontend",
    "todo-app-backend"
  ]
}

module "rds" {
  source               = "../../modules/rds"
  name                 = "${var.project_name}-dev"
  vpc_id               = module.vpc.vpc_id
  private_subnet_cidrs = module.vpc.private_subnet_cidrs
  db_subnet_group_name = module.vpc.db_subnet_group_name
  ssm_prefix           = "/todo-app/dev"
}

module "eks" {
  source              = "../../modules/eks"
  name                = "${var.project_name}-dev"
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  kubernetes_version  = "1.35"
  node_instance_types = ["t3.large"]
  node_desired_size   = 2
  tags                = local.tags
}

module "runner" {
  source                      = "../../modules/runner"
  name                        = "${var.project_name}-dev"
  vpc_id                      = module.vpc.vpc_id
  subnet_id                   = module.vpc.private_subnet_ids[0]
  github_repo                 = var.github_repo
  github_token_parameter_name = var.runner_github_token_parameter_name
  ecr_repository_arns         = values(module.ecr.repository_arns)
}

module "vpn" {
  source            = "../../modules/vpn"
  name              = "${var.project_name}-dev"
  vpc_id            = module.vpc.vpc_id
  public_subnet_id  = module.vpc.public_subnet_ids[0]
  vpc_cidr_block    = module.vpc.vpc_cidr_block
  developer_ip_cidr = var.developer_ip_cidr
  client_public_key = var.wireguard_client_public_key
  wireguard_port    = 51820
}

module "route53" {
  source       = "../../modules/route53"
  zone_name    = var.domain_name
  record_name  = var.app_host
  alb_dns_name = var.alb_dns_name
  alb_zone_id  = var.alb_dns_name != "" ? data.aws_elb_hosted_zone_id.main.id : ""
}
