output "public_ip" {
  value = aws_eip.vpn.public_ip
}

output "instance_id" {
  value = aws_instance.vpn.id
}

output "client_allowed_ips" {
  value = var.vpc_cidr_block
}
