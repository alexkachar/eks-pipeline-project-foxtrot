resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_security_group" "db" {
  name        = "${var.name}-rds"
  description = "PostgreSQL from private subnets"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.private_subnet_cidrs
  }
}

resource "aws_db_instance" "this" {
  identifier                 = var.name
  engine                     = "postgres"
  instance_class             = var.instance_class
  allocated_storage          = 20
  max_allocated_storage      = 100
  storage_type               = "gp3"
  storage_encrypted          = true
  db_name                    = var.database_name
  username                   = var.username
  password                   = random_password.db.result
  db_subnet_group_name       = var.db_subnet_group_name
  vpc_security_group_ids     = [aws_security_group.db.id]
  publicly_accessible        = false
  skip_final_snapshot        = true
  deletion_protection        = false
  auto_minor_version_upgrade = true
  backup_retention_period    = 1
}

resource "aws_ssm_parameter" "db" {
  for_each = {
    db-host     = aws_db_instance.this.address
    db-port     = tostring(aws_db_instance.this.port)
    db-name     = var.database_name
    db-user     = var.username
    db-password = random_password.db.result
  }

  name      = "${var.ssm_prefix}/${each.key}"
  type      = each.key == "db-password" ? "SecureString" : "String"
  value     = each.value
  overwrite = true
}
