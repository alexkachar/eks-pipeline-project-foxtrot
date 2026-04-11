output "fqdn" {
  value = try(aws_route53_record.app[0].fqdn, "")
}
