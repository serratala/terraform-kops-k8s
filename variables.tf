variable "name" {
  default = "example.com"
}

variable "region" {
  default = "us-west-2"
}

variable "azs" {
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
  type    = "list"
}

variable "env" {
  default = "dev"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "amis" {
  type = "map"
  default = {
    "us-east-1" = "ami-b374d5a5" # CentOS 7
    "us-west-2" = "ami-3ecc8f46" # CentOS 7
  }
}