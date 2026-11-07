# ============================================================
# SECTION: PROVIDERS
# ============================================================
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>6.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# ============================================================
# SECTION: DATA SOURCES
# ============================================================

# 1.0 AVAILABILITY ZONES
data "aws_availability_zones" "available" {
  state = "available"
}

# 2.0 AMI - Fetch the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ============================================================
# SECTION: LOCALS
# ============================================================
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "chesa"
  }
}
# ============================================================
# SECTION: NETWORKING
# ============================================================

# 1.0 VPC Resource
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# 2.0 SUBNETS
# 2.1 Public Subnet - Create two public subnets in two different availability zones
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr_block[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-subnet-${count.index + 1}"
  }
}
# 2.2 Private Subnet - Create two private subnets in two different availablity zones
resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr_block[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-private-subnet-${count.index + 1}"
  }
}

# 3.0 INTERNET GATEWAY
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# 4.0 ELASTIC IPs
# 4.1 For NAT Gateway
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${local.name_prefix}-nat-eip"
  }
}
# 4.2 For Bastion Host
resource "aws_eip" "bastion" {
  instance   = aws_instance.bastion.id
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${local.name_prefix}-bastion-eip"
  }
}

# 5.0 NAT GATEWAY
# For private subnet outbound access, lives on one public subnet
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${local.name_prefix}-nat-gw"
  }
}

# 6.0 ROUTE TABLES
# 6.1.0 Public subnet Route Table and Route Table Association - points all traffic from 0.0.0.0/0 to the IGW and can also point all the data packets arriving to the right resource it needs to arrive at within the public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}
# 6.1.1 Two route table associations, one for each public subnet
resource "aws_route_table_association" "public" {
  count          = 2
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public[count.index].id
}

# 6.2.0 Private subnet Route Table and Route Table Association - points 0.0.0.0/0 traffic to the NAT gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-private-rt"
  }
}
# 6.2.1 Two route table associations, one for each private subnet
resource "aws_route_table_association" "private" {
  count          = 2
  route_table_id = aws_route_table.private.id
  subnet_id      = aws_subnet.private[count.index].id
}

# ============================================================
# SECTION: SECURITY GROUPS
# ============================================================

# 1.0 BACKEND SECURITY GROUP
resource "aws_security_group" "backend-sg" {
  name        = "${local.name_prefix}-backend-sg"
  description = "Allow HTTP and SSH from ALB and Bastion respectively."
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-backend-sg"
  }
}
# 1.0.1 Accept inbound access on port 80 from only ALB
resource "aws_vpc_security_group_ingress_rule" "backend_allow_http" {
  ip_protocol                  = "tcp"
  security_group_id            = aws_security_group.backend-sg.id
  referenced_security_group_id = aws_security_group.alb-sg.id
  from_port                    = 8080
  to_port                      = 8080
}
# 1.0.2 Accept inbound access on port 22 from only Bastion Host
resource "aws_vpc_security_group_ingress_rule" "backend_allow_ssh" {
  ip_protocol                  = "tcp"
  security_group_id            = aws_security_group.backend-sg.id
  referenced_security_group_id = aws_security_group.bastion-sg.id
  from_port                    = 22
  to_port                      = 22
}
# 1.0.3 Allow all outbound rules
resource "aws_vpc_security_group_egress_rule" "backend_allow_all_traffic" {
  ip_protocol       = "-1"
  security_group_id = aws_security_group.backend-sg.id
  cidr_ipv4         = "0.0.0.0/0"
}

# 2.0 BASTION SECURITY GROUP
resource "aws_security_group" "bastion-sg" {
  name        = "${local.name_prefix}-bastion-sg"
  description = "Allow SSH from your current IP address only."
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-bastion-sg"
  }
}
# 2.0.1 Accept inbound access on port 22 from only my personal IP
resource "aws_vpc_security_group_ingress_rule" "bastion_allow_ssh" {
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.bastion-sg.id
  cidr_ipv4         = var.my_ip
  from_port         = 22
  to_port           = 22
}
# 2.0.2 Allow all outbound rules
resource "aws_vpc_security_group_egress_rule" "bastion_allow_all_traffic" {
  ip_protocol       = "-1"
  security_group_id = aws_security_group.bastion-sg.id
  cidr_ipv4         = "0.0.0.0/0"
}

# 3.0 APPLICATION LOAD BALANCER SECURITY GROUP
resource "aws_security_group" "alb-sg" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Allow HTTP and HTTPS from anywhere."
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-alb-sg"
  }
}
# 3.0.1 Accept inbound access on port 80 from internet
resource "aws_vpc_security_group_ingress_rule" "alb_allow_http" {
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.alb-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
}
# 3.0.2 Accept inbound access on port 443 from internet
resource "aws_vpc_security_group_ingress_rule" "alb_allow_https" {
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.alb-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
}
# 3.0.3 Allow all outbound rules
resource "aws_vpc_security_group_egress_rule" "alb_allow_all_traffic" {
  ip_protocol       = "-1"
  security_group_id = aws_security_group.alb-sg.id
  cidr_ipv4         = "0.0.0.0/0"
}

# 4.0 MONGODB SECURITY GROUP
resource "aws_security_group" "mongodb-sg" {
  name        = "${local.name_prefix}-mongodb-sg"
  description = "Allow 27017 from Backend only."
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-mongodb-sg"
  }
}
# 4.0.1 Accept inbound access on port 27017 from only Backend
resource "aws_vpc_security_group_ingress_rule" "mongodb_allow_ssh" {
  ip_protocol                  = "tcp"
  security_group_id            = aws_security_group.mongodb-sg.id
  referenced_security_group_id = aws_security_group.backend-sg.id
  from_port                    = 27017
  to_port                      = 27017
}
# 4.0.2 Allow all outbound rules
resource "aws_vpc_security_group_egress_rule" "mongodb_allow_all_traffic" {
  ip_protocol       = "-1"
  security_group_id = aws_security_group.mongodb-sg.id
  cidr_ipv4         = "0.0.0.0/0"
}

# ============================================================
# SECTION: COMPUTE - EC2 INSTANCES
# ============================================================

# 1.0 BASTION HOST
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.bastion-sg.id]
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null

  tags = {
    Name = "${local.name_prefix}-bastion-host"
  }
}

# 2.0 BACKEND SERVER
resource "aws_instance" "backend" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.backend-sg.id]
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null
  # Bash script to install Docker and Docker Compose on startup
  user_data = file("${path.module}/user_data/backend_setup.sh")
  user_data_replace_on_change = true

  depends_on = [ aws_nat_gateway.main, aws_route_table_association.private ]
  
  tags = {
    Name = "${local.name_prefix}-backend-server"
  }
}

# 3.0 MONGODB SERVER
resource "aws_instance" "mongodb" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[1].id
  vpc_security_group_ids = [aws_security_group.mongodb-sg.id]
  # Bash script to install MongoDB on startup
  user_data = file("${path.module}/user_data/backend_setup.sh")
  user_data_replace_on_change = true

  tags = {
    Name = "${local.name_prefix}-mongodb-server"
  }
}

# ============================================================
# SECTION: APPLICATION LOAD BALANCER
# ============================================================

resource "aws_lb" "alb" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb-sg.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  enable_deletion_protection = false

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

resource "aws_lb_target_group" "alb_tg" {
  name        = "${local.name_prefix}-alb-target-group"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"
  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name = "${local.name_prefix}-alb-target-group"
  }
}

resource "aws_lb_target_group_attachment" "alb_tg_attachment" {
  target_group_arn = aws_lb_target_group.alb_tg.arn
  target_id        = aws_instance.backend.id
  port             = 8080
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_tg.arn
  }
}
