variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "github_token_parameter_name" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "ecr_repository_arns" {
  type = list(string)
}
