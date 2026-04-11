output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr_block" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = values(aws_subnet.public)[*].id
}

output "private_subnet_ids" {
  value = values(aws_subnet.private)[*].id
}

output "database_subnet_ids" {
  value = values(aws_subnet.database)[*].id
}

output "private_subnet_cidrs" {
  value = values(aws_subnet.private)[*].cidr_block
}

output "db_subnet_group_name" {
  value = aws_db_subnet_group.this.name
}
