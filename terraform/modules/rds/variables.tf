variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "db_subnet_group_name" {
  type = string
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "database_name" {
  type    = string
  default = "todo"
}

variable "username" {
  type    = string
  default = "todo"
}

variable "ssm_prefix" {
  type    = string
  default = "/todo-app/dev"
}
