variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_id" {
  type = string
}

variable "vpc_cidr_block" {
  type = string
}

variable "developer_ip_cidrs" {
  type        = list(string)
  description = "List of developer IP CIDRs allowed to connect to WireGuard (UDP 51820)."
}

variable "client_public_key" {
  type        = string
  description = "WireGuard client public key to authorize. Leave empty to boot only the server."
  default     = ""
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "wireguard_port" {
  type    = number
  default = 51820
}
