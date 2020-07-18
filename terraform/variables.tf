
variable region {
  default = "eu-west-2"
}

variable "availability_zone_names" {
  type    = list(string)
  default = ["eu-west-2a", "eu-west-2b"]
}

variable cidr_block {
  default = "172.16.0.0/22"
}

variable public_cidr_block_lb {
  default = "172.16.0.1/24"
}

variable private_cidr_block_ec2 {
  default = "172.16.1.1/24"
} 

variable private_cidr_block_rds {
  default = "172.16.2.1/24"
}

variable mysqluser {
  default = "root"
}

variable mysqlpassprod {
  default = "Passw0rdPr0d"
}

variable mysqlpassdev {
  default = "Passw0rdD3v"
}

variable mysqlpasstest {
  default = "Passw0rdT3st"
}
