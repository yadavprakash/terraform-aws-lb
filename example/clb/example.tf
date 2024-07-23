provider "aws" {
  region = "us-east-1"
}

locals {
  name        = "clb"
  environment = "test"
}


module "vpc" {
  source                              = "git::https://github.com/yadavprakash/terraform-aws-vpc.git?ref=v1.0.0"
  name                                = "app"
  environment                         = "test"
  cidr_block                          = "10.0.0.0/16"
  enable_flow_log                     = true # Flow logs will be stored in cloudwatch log group. Variables passed in default.
  create_flow_log_cloudwatch_iam_role = true
  additional_cidr_block               = ["172.3.0.0/16", "172.2.0.0/16"]
  dhcp_options_domain_name            = "service.consul"
  dhcp_options_domain_name_servers    = ["127.0.0.1", "10.10.0.2"]
}

module "public_subnets" {
  source             = "git::https://github.com/yadavprakash/terraform-aws-subnet.git?ref=v1.0.0"
  name               = local.name
  environment        = local.environment
  availability_zones = ["us-east-1a", "us-east-1b"]
  type               = "public"
  vpc_id             = module.vpc.id
  cidr_block         = module.vpc.vpc_cidr_block
  igw_id             = module.vpc.igw_id
  ipv6_cidr_block    = module.vpc.ipv6_cidr_block
}


module "iam-role" {
  source             = "git::https://github.com/yadavprakash/terraform-aws-iam-role.git?ref=v1.0.0"
  name               = local.name
  environment        = local.environment
  assume_role_policy = data.aws_iam_policy_document.default.json

  policy_enabled = true
  policy         = data.aws_iam_policy_document.iam-policy.json
}

data "aws_iam_policy_document" "default" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "iam-policy" {
  statement {
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
    "ssmmessages:OpenDataChannel"]
    effect    = "Allow"
    resources = ["*"]
  }
}

module "ec2" {
  source                      = "git::https://github.com/yadavprakash/terraform-aws-ec2.git?ref=v1.0.0"
  name                        = local.name
  environment                 = local.environment
  vpc_id                      = module.vpc.id
  ssh_allowed_ip              = ["0.0.0.0/0"]
  ssh_allowed_ports           = [22]
  instance_count              = 2
  ami                         = "ami-0a2e7efb4257c0907"
  instance_type               = "t2.nano"
  monitoring                  = false
  tenancy                     = "default"
  public_key                  = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDWdZXx5WsXHQbKhRrunupZe6gayxaGLaIAtwz+xcN7Ln3DvyHJPv56IGeFjc6DPJEwavtXugD+ndVkctRlRpmg5xFek1I4+FNhqmTiVqn6DN+cNkdMEBVm8ILo8+AY8WKDuJUVxR+d2AmaBCL8EGfpMAFA1AHEpgceKq3nJbKvHlxf6obVG1uSfNR5HNvIFfq85EGSUmjY3Z6sXV4Uy201+tU6yRpu5Y0lj/jMC3i8ulXFu1245o4lNDjjUQQh4c2bGLi0L3/CDOHCFeBJaxUWC9yo18LgIv+m4YpSsRIWu014keIrJO4O+vyoybTCVSLl9kWOs8wSXjrg1zqg5VqE/w5XqI+C3Wcrf4aTDJ17oFm1UCVmtpUbHNvd3DoXInozkxk6FRAQGWz4Ni0cZrvFF6QCH5dU+xy96VNIDP9t/iwlWO86/AbLEWOrr1HSaaVujswdTHfw8kferyJuhAd20t9kNgGc2k7hsbaRNbbykP8KhJeHoDIBFILQVWXhgFc= manoj@manoj"
  subnet_ids                  = tolist(module.public_subnets.public_subnet_id)
  iam_instance_profile        = module.iam-role.name
  assign_eip_address          = true
  associate_public_ip_address = true
  instance_profile_enabled    = true

  ebs_optimized      = false
  ebs_volume_enabled = true
  ebs_volume_type    = "gp2"
  ebs_volume_size    = 30
}

module "clb" {
  source = "./../../"

  name               = "app"
  load_balancer_type = "classic"
  clb_enable         = true
  internal           = true
  vpc_id             = module.vpc.id
  target_id          = module.ec2.instance_id
  subnets            = module.public_subnets.public_subnet_id
  with_target_group  = true
  listeners = [
    {
      lb_port            = 22000
      lb_protocol        = "TCP"
      instance_port      = 22000
      instance_protocol  = "TCP"
      ssl_certificate_id = null
    },
    {
      lb_port            = 4444
      lb_protocol        = "TCP"
      instance_port      = 4444
      instance_protocol  = "TCP"
      ssl_certificate_id = null
    }
  ]
  health_check_target              = "TCP:4444"
  health_check_timeout             = 10
  health_check_interval            = 30
  health_check_unhealthy_threshold = 5
  health_check_healthy_threshold   = 5
}

