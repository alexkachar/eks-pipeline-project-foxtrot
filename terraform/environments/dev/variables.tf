variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "project-foxtrot"
}

variable "domain_name" {
  type    = string
  default = "alexanderkachar.com"
}

variable "app_host" {
  type    = string
  default = "todo.alexanderkachar.com"
}

variable "monitoring_host" {
  type    = string
  default = "monitoring.alexanderkachar.com"
}

variable "github_repo" {
  type    = string
  default = "alexkachar/eks-pipeline-project-foxtrot"
}

variable "runner_github_token_parameter_name" {
  type    = string
  default = "/github/actions/foxtrot/pat"
}

variable "developer_ip_cidrs" {
  type        = list(string)
  description = "Developer IP CIDRs allowed to connect to WireGuard."
}

variable "wireguard_client_public_key" {
  type    = string
  default = ""
}

variable "enable_cluster_addons" {
  type        = bool
  description = "Install Kubernetes and Helm resources. Enable only after connecting through the VPN to the private EKS API."
  default     = false
}

variable "alb_dns_name" {
  type    = string
  default = ""
}

variable "monitoring_alb_dns_name" {
  type    = string
  default = ""
}
