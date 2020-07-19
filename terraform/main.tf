provider "aws" {
  region = var.region
}
# Deploys a new VPC using the cidr block defined in variables
module "vpc" {
  source     = "git::https://github.com/cloudposse/terraform-aws-vpc.git"
  namespace  = "vpc"
  stage      = "prod"
  name       = "notejam"
  attributes = []
  tags       = {}
  delimiter  = "-"
  cidr_block = var.cidr_block
}
#Public Subnet for load balancer
module "public_subnets_lb" {
  source              = "git::https://github.com/cloudposse/terraform-aws-multi-az-subnets.git"
  namespace           = "sl"
  stage               = "prod"
  name                = "notejam"
  availability_zones  = var.availability_zone_names
  vpc_id              = module.vpc.vpc_id
  cidr_block          = var.public_cidr_block_lb
  type                = "public"
  igw_id              = module.vpc.igw_id
  nat_gateway_enabled = "true"
}
#Private subnet for EC2 instances
module "private_subnets_ec2" {
  source             = "git::https://github.com/cloudposse/terraform-aws-multi-az-subnets.git"
  namespace          = "sl"
  stage              = "prod"
  name               = "notejam"
  availability_zones = var.availability_zone_names
  vpc_id             = module.vpc.vpc_id
  cidr_block         = var.private_cidr_block_ec2
  type               = "private"

  az_ngw_ids = module.public_subnets_lb.az_ngw_ids
}
#Private subnet for rds
module "private_subnets_rds" {
  source             = "git::https://github.com/cloudposse/terraform-aws-multi-az-subnets.git"
  namespace          = "sl"
  stage              = "prod"
  name               = "notejam"
  availability_zones = var.availability_zone_names
  vpc_id             = module.vpc.vpc_id
  cidr_block         = var.private_cidr_block_rds
  type               = "private"
  
}

# Elastic Beanstalk Application

module "elastic_beanstalk_application" {
  source      = "git::https://github.com/cloudposse/terraform-aws-elastic-beanstalk-application.git"
  namespace   = "sl"
  stage       = "prod"
  name        = "notejam"
  attributes  = []
  tags        = {}
  delimiter   = "-"
  description = "Note Jam"
}

# Elastic Beanstalk Prod Environment

module "elastic_beanstalk_environment_prod" {
  source                     = "git::https://github.com/cloudposse/terraform-aws-elastic-beanstalk-environment"
  namespace                  = "sl"
  stage                      = "prod"
  name                       = "notejamapp"
  attributes                 = []
  tags                       = {}
  delimiter                  = "-"
  description                = "Prod Environment"
  region                     = var.region
  availability_zone_selector = "Any 2"
  wait_for_ready_timeout             = "20m"
  elastic_beanstalk_application_name = module.elastic_beanstalk_application.elastic_beanstalk_application_name
  environment_type                   = "LoadBalanced"
  loadbalancer_type                  = "application"
  elb_scheme                         = "public"
  tier                               = "WebServer"
  version_label                      = ""
  force_destroy                      = true

  instance_type    = "t2.micro"
  root_volume_size = 8
  root_volume_type = "gp2"
  autoscale_min             = 1
  autoscale_max             = 4
  autoscale_measure_name    = "CPUUtilization"
  autoscale_statistic       = "Average"
  autoscale_unit            = "Percent"
  autoscale_lower_bound     = 30
  autoscale_lower_increment = -1
  autoscale_upper_bound     = 80
  autoscale_upper_increment = 1

  vpc_id                  = module.vpc.vpc_id
  loadbalancer_subnets    = values(module.public_subnets_lb.az_subnet_ids)
  application_subnets     = values(module.private_subnets_ec2.az_subnet_ids)
  allowed_security_groups = [module.rds_instance_prod.security_group_id, module.vpc.vpc_default_security_group_id]

  rolling_update_enabled  = true
  rolling_update_type     = "Health"
  updating_min_in_service = 1
  updating_max_batch      = 1
  healthcheck_url         = "/"
  application_port        = 80

  solution_stack_name = "64bit Amazon Linux 2018.03 v4.15.0 running Node.js"

  ssh_listener_enabled = false

  additional_settings = [
     {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "MatcherHTTPCode"
    value     = "200,301,302"
    }
    ]

  env_vars             = {
  "MYSQL_HOST"         = module.rds_instance_prod.instance_address
  "MYSQL_USER"         = var.mysqluser
  "MYSQL_PASSWORD"     = var.mysqlpassprod
  "MYSQL_TCP_PORT"     = "3306" 
  "NOTEJAM_PORT"       = "8081"
  }
}

module "rds_instance_prod" {
  source                      = "git::https://github.com/cloudposse/terraform-aws-rds.git"
  namespace                   = "sl"
  stage                       = "prod"
  name                        = "notejamdb"
  database_name               = "notejam"
  database_user               = var.mysqluser
  database_password           = var.mysqlpassprod
  database_port               = 3306
  #multi az for redundancy
  multi_az                    = true
  storage_type                = "gp2"
  allocated_storage           = 5
  storage_encrypted           = true
  engine                      = "mysql"
  engine_version              = "8.0.17"
  # instance class smallest for demo purposes that supports encryption at rest
  instance_class              = "db.t2.small"
  db_parameter_group          = "mysql8.0"
  publicly_accessible         = false
  vpc_id                      = module.vpc.vpc_id
  subnet_ids                  = values(module.private_subnets_rds.az_subnet_ids)
  security_group_ids          = [module.elastic_beanstalk_environment_prod.security_group_id]
  apply_immediately           = true
  backup_retention_period     = 35
  backup_window               = "22:00-03:00"
  copy_tags_to_snapshot       = true
}

# Elastic Beanstalk Dev Environment

module "elastic_beanstalk_environment_dev" {
  source                     = "git::https://github.com/cloudposse/terraform-aws-elastic-beanstalk-environment.git"
  namespace                  = "sl"
  stage                      = "dev"
  name                       = "notejamapp"
  attributes                 = []
  tags                       = {}
  delimiter                  = "-"
  description                = "Dev Environment"
  region                     = var.region
  availability_zone_selector = "Any 2"
  wait_for_ready_timeout             = "20m"
  elastic_beanstalk_application_name = module.elastic_beanstalk_application.elastic_beanstalk_application_name
  environment_type                   = "LoadBalanced"
  loadbalancer_type                  = "application"
  elb_scheme                         = "public"
  tier                               = "WebServer"
  version_label                      = ""
  force_destroy                      = true

  instance_type    = "t2.micro"
  #enable spot instances for dev & test environment cost savings
  enable_spot_instances = true
  spot_max_price = 0.01
  root_volume_size = 8
  root_volume_type = "gp2"
  autoscale_min             = 1
  autoscale_max             = 4
  autoscale_measure_name    = "CPUUtilization"
  autoscale_statistic       = "Average"
  autoscale_unit            = "Percent"
  autoscale_lower_bound     = 30
  autoscale_lower_increment = -1
  autoscale_upper_bound     = 80
  autoscale_upper_increment = 1

  vpc_id                  = module.vpc.vpc_id
  loadbalancer_subnets    = values(module.public_subnets_lb.az_subnet_ids)
  application_subnets     = values(module.private_subnets_ec2.az_subnet_ids)
  allowed_security_groups = [module.rds_instance_dev.security_group_id, module.vpc.vpc_default_security_group_id]

  rolling_update_enabled  = true
  rolling_update_type     = "Health"
  updating_min_in_service = 1
  updating_max_batch      = 1
  healthcheck_url         = "/"
  application_port        = 80

  solution_stack_name = "64bit Amazon Linux 2018.03 v4.15.0 running Node.js"

  ssh_listener_enabled = false

  
  additional_settings = [
     {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "MatcherHTTPCode"
    value     = "200,301,302"
    }
    ]
  
  env_vars             = {
  "MYSQL_HOST"         = module.rds_instance_dev.instance_address
  "MYSQL_USER"         = var.mysqluser
  "MYSQL_PASSWORD"     = var.mysqlpassdev
  "MYSQL_TCP_PORT"     = "3306" 
  "NOTEJAM_PORT"       = "8081"
  }
}


module "rds_instance_dev" {
  source                      = "git::https://github.com/cloudposse/terraform-aws-rds.git"
  namespace                   = "sl"
  stage                       = "dev"
  name                        = "notejamdb"
  database_name               = "notejam"
  database_user               = var.mysqluser
  database_password           = var.mysqlpassdev
  database_port               = 3306
  multi_az                    = false
  storage_type                = "standard"
  #Storage type set to standard (magnetic) for dev and test instances, identify whether this is sufficient.
  allocated_storage           = 5
  storage_encrypted           = true
  engine                      = "mysql"
  engine_version              = "8.0.17"
  # instance class smallest for demo purposes that supports encryption at rest
  instance_class              = "db.t2.small"
  db_parameter_group          = "mysql8.0"
  publicly_accessible         = false
  vpc_id                      = module.vpc.vpc_id
  subnet_ids                  = values(module.private_subnets_rds.az_subnet_ids)  
  security_group_ids          = [module.elastic_beanstalk_environment_dev.security_group_id]
  apply_immediately           = true
  backup_retention_period     = 35
  backup_window               = "22:00-03:00"
  copy_tags_to_snapshot       = true
}

# Elastic Beanstalk Test Environment

module "elastic_beanstalk_environment_test" {
  source                     = "git::https://github.com/cloudposse/terraform-aws-elastic-beanstalk-environment.git"
  namespace                  = "sl"
  stage                      = "test"
  name                       = "notejamapp"
  attributes                 = []
  tags                       = {}
  delimiter                  = "-"
  description                = "Test Environment"
  region                     = var.region
  availability_zone_selector = "Any 2"
  wait_for_ready_timeout             = "20m"
  elastic_beanstalk_application_name = module.elastic_beanstalk_application.elastic_beanstalk_application_name
  environment_type                   = "LoadBalanced"
  loadbalancer_type                  = "application"
  elb_scheme                         = "public"
  tier                               = "WebServer"
  version_label                      = ""
  force_destroy                      = true

  instance_type    = "t2.micro"
  #enable spot instances for dev & test environment cost savings
  enable_spot_instances = true
  spot_max_price = 0.01
  root_volume_size = 8
  root_volume_type = "gp2"
  autoscale_min             = 1
  autoscale_max             = 4
  autoscale_measure_name    = "CPUUtilization"
  autoscale_statistic       = "Average"
  autoscale_unit            = "Percent"
  autoscale_lower_bound     = 30
  autoscale_lower_increment = -1
  autoscale_upper_bound     = 80
  autoscale_upper_increment = 1

  vpc_id                  = module.vpc.vpc_id
  loadbalancer_subnets    = values(module.public_subnets_lb.az_subnet_ids)
  application_subnets     = values(module.private_subnets_ec2.az_subnet_ids)
  allowed_security_groups = [module.rds_instance_test.security_group_id, module.vpc.vpc_default_security_group_id]

  rolling_update_enabled  = true
  rolling_update_type     = "Health"
  updating_min_in_service = 1
  updating_max_batch      = 1
  healthcheck_url         = "/"
  application_port        = 80

  solution_stack_name = "64bit Amazon Linux 2018.03 v4.15.0 running Node.js"

  ssh_listener_enabled = false

  
  additional_settings = [
     {
    namespace = "aws:elasticbeanstalk:environment:process:default"
    name      = "MatcherHTTPCode"
    value     = "200,301,302"
    }
    ]
  
  env_vars             = {
  "MYSQL_HOST"         = module.rds_instance_test.instance_address
  "MYSQL_USER"         = var.mysqluser
  "MYSQL_PASSWORD"     = var.mysqlpasstest
  "MYSQL_TCP_PORT"     = "3306" 
  "NOTEJAM_PORT"       = "8081"
  }
}

module "rds_instance_test" {
  source                      = "git::https://github.com/cloudposse/terraform-aws-rds.git"
  namespace                   = "sl"
  stage                       = "test"
  name                        = "notejamdb"
  database_name               = "notejam"
  database_user               = var.mysqluser
  database_password           = var.mysqlpasstest
  database_port               = 3306
  multi_az                    = false
  storage_type                = "standard"
  #Storage type set to standard (magnetic) for dev and test instances, identify whether this is sufficient.
  allocated_storage           = 5
  storage_encrypted           = true
  engine                      = "mysql"
  engine_version              = "8.0.17"
  instance_class              = "db.t2.small"
  # instance class smallest for demo purposes that supports encryption at rest
  db_parameter_group          = "mysql8.0"
  publicly_accessible         = false
  vpc_id                      = module.vpc.vpc_id
  subnet_ids                  = values(module.private_subnets_rds.az_subnet_ids)  
  security_group_ids          = [module.elastic_beanstalk_environment_test.security_group_id]
  apply_immediately           = true
  backup_retention_period     = 35
  backup_window               = "22:00-03:00"
  copy_tags_to_snapshot       = true
}


#Configure AWS Backup for Prod DB. Dev & test currently rely on auto backups only, duplicate this block to use AWS backup for those as required.
module "aws_backup_prod" {
  source = "git::https://github.com/cloudposse/terraform-aws-backup.git"
  backup_resources = [module.rds_instance_prod.instance_arn]
  name = "DBBackup"
  stage = "prod"
  delete_after = 1080
  delimiter = "-"
}
