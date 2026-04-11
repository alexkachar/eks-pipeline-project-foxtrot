data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_security_group" "vpn" {
  name        = "${var.name}-vpn"
  description = "WireGuard VPN"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = var.wireguard_port
    to_port     = var.wireguard_port
    protocol    = "udp"
    cidr_blocks = [var.developer_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "vpn" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.vpn.id]
  associate_public_ip_address = true
  source_dest_check           = false

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    client_public_key = var.client_public_key
    vpc_cidr_block    = var.vpc_cidr_block
    wireguard_port    = var.wireguard_port
  })

  tags = {
    Name = "${var.name}-vpn"
  }
}
