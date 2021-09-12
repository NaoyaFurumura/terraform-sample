provider "aws" {
  profile = "default"
  region  = "ap-northeast-1"
}

resource "aws_vpc" "learn_vpc" {
  cidr_block           = "10.0.0.1/16"
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    name = "learn_vpc"
  }
}

resource "aws_subnet" "public_subnet_1a" {
  vpc_id                  = aws_vpc.learn_vpc.id
  cidr_block              = "10.1.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-northeast-1a"
  tags = {
    name = "public-subnet-for-web1"
  }
}

resource "aws_subnet" "public_subnet_1c" {
  vpc_id                  = aws_vpc.learn_vpc.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = true
  tags = {
    name = "public-subnet-for-web2"
  }
}

resource "aws_subnet" "private_subnet_1a" {
  vpc_id            = aws_vpc.learn_vpc.id
  cidr_block        = "10.1.1.1/24"
  availability_zone = "ap-northeast-1a"
  tags = {
    name = "private-subnet-for-db"
  }
}

resource "aws_subnet" "private_subnet_1c" {
  vpc_id            = aws_vpc.learn_vpc.id
  cidr_block        = "10.1.2.1/24"
  availability_zone = "ap-northeast-1c"
  tags = {
    name = "private-subnet-for-db"
  }
}

resource "aws_internet_gateway" "learn_internet_gw" {
  vpc_id = aws_vpc.learn_vpc.id
  tags = {
    Name = "learn_internet_gw"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.learn_vpc.id

  tags = {
    Name = "laern-public-route-table"
  }
}

resource "aws_route" "internetGw" {
  destination_cidr_block = "0.0.0.0/0"
  route_table_id         = aws_route_table.public_route_table.id
  gateway_id             = aws_internet_gateway.learn_internet_gw.id
}

resource "aws_route_table_assocication" "public1a" {
  subnet_id      = aws_subnet.public_subnet_1a.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_assocication" "public1c" {
  subnet_id      = aws_subnet.public_subnet_1c.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_security_group" "web_security_group" {
  vpc_id      = aws_vpc.learn_vpc.id
  name        = "web_security_group"
  description = "allow ssh and http "
  ingress = [
    {
      protocol        = "tcp"
      from_port       = "80"
      to_port         = "80"
      security_groups = "${aws_security_group.elb_security_group.id}"
      }, {
      protocol        = "ssh"
      from_port       = "20"
      to_port         = "20"
      security_groups = "${aws_security_group.elb_security_group.id}"
  }]

  egress = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = -1
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
  tags = [{
    Name = "web-security-group"
  }]
}

resource "aws_security_group" "elb_security_group" {
  vpc_id      = aws_vpc.learn_vpc.id
  name        = "elb_security_group"
  description = "elb security group"
  ingress = [
    {
      protocol    = "80"
      from_port   = "80"
      to_port     = "80"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

resource "aws_security_group" "db_security_group" {
  vpc_id      = aws_vpc.learn_vpc.id
  name        = "db_security_group"
  description = "db_security_group"
  ingress = [{
    from_port       = "3306"
    to_port         = "3306"
    protocol        = "tcp"
    security_groups = "${aws_security_group.web_security_group.id}"
  }]
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db_subnet_group"
  subnet_ids = [aws_subnet.private_subnet_1a.id, aws_subnet.private_subnet_1c.id]
  tags = {
    "Name" = "db_subnet_group"
  }
}

resource "aws_db_instance" "db_instance" {
  identifier             = "learn-mysql"
  engine                 = "mysql"
  engine_version         = "5.7"
  allocated_storage      = 20
  multi_az               = true
  instance_class         = "db.t3.micro"
  password               = "rootpassword"
  username               = "root"
  port                   = "3306"
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_security_group.id]
  //cloudWatch書いてないけど一応
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]
}
resource "aws_key_pair" "web_key" {
  key_name   = "web_key"
  public_key = file(var.key_path)
}

resource "aws_instance" "web1" {
  instance_type               = "t3.micro"
  ami                         = " ami-0653200a3a683e0d5"
  security_groups             = [aws_security_group.web_security_group]
  subnet_id                   = aws_subnet.public_subnet_1a.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.web_key.key_name
  tags = {
    "Name" = "web1"
  }
}

resource "aws_instance" "web2" {
  instance_type               = "t3.micro"
  ami                         = " ami-0653200a3a683e0d5"
  security_groups             = [aws_security_group.web_security_group]
  subnet_id                   = aws_subnet.public_subnet_1c.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.web_key.key_name
  tags = {
    "Name" = "web2"
  }
}

resource "aws_lb_target_group_attachment" "attach_web1" {
  target_group_arn = aws_lb_target_group.lb_target_grp.arn
  target_id        = aws_instance.web1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "attach_web2" {
  target_group_arn = aws_lb_target_group.lb_target_grp.arn
  target_id        = aws_instance.web2.id
  port             = 80
}


resource "aws_lb_target_group" "lb_target_grp" {
  vpc_id      = aws_vpc.learn_vpc.id
  port        = 80
  name        = "lb_target_grp"
  protocol    = "HTTP"
  target_type = "instance"
}





