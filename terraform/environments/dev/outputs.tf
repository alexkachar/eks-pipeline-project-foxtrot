output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "frontend_repository_url" {
  value = module.ecr.repository_urls["todo-app-frontend"]
}

output "backend_repository_url" {
  value = module.ecr.repository_urls["todo-app-backend"]
}

output "vpn_public_ip" {
  value = module.vpn.public_ip
}

output "vpn_allowed_ips" {
  value = module.vpn.client_allowed_ips
}

output "app_fqdn" {
  value = module.route53.fqdn
}
