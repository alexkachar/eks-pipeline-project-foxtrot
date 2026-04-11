output "public_ip" {
  value = aws_instance.vpn.public_ip
}

output "client_allowed_ips" {
  value = var.vpc_cidr_block
}
