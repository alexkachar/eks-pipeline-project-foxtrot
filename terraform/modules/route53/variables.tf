variable "zone_name" {
  type = string
}

variable "record_name" {
  type = string
}

variable "alb_dns_name" {
  type    = string
  default = ""
}

variable "alb_zone_id" {
  type    = string
  default = ""
}
