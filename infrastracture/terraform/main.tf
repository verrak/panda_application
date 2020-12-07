provider "aws" {
  region = "us-east-1"
  # profile = panda # tylko gdy istnieje taki --profile w ~/.aws/credentials
}

resource "aws_vpc" "vpc" {
    cidr_block = "10.83.0.0/16"
    enable_dns_support   = true
    enable_dns_hostnames = true
    tags       = {
        Name = "Terraform VPC"
    }
}

resource "aws_internet_gateway" "internet_gateway" {
    vpc_id = aws_vpc.vpc.id
}


resource "aws_route_table" "public_route_table" {
    vpc_id = aws_vpc.vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.internet_gateway.id
    }
}

resource "aws_route_table_association" "public_route_table_association" {
    subnet_id = aws_subnet.pub_subnet.id
    route_table_id = aws_route_table.public_route_table.id
}

resource "aws_subnet" "pub_subnet" {
    vpc_id                  = aws_vpc.vpc.id
    cidr_block              = "10.83.16.0/20"
    map_public_ip_on_launch = true
    availability_zone = "us-east-1a"
}

resource "aws_security_group" "sg-pub" {
    vpc_id      = aws_vpc.vpc.id

    ingress {
        from_port       = 80
        to_port         = 80
        protocol        = "tcp"
        cidr_blocks     = ["0.0.0.0/0"]
    }

    ingress {
        from_port       = 8080
        to_port         = 8080
        protocol        = "tcp"
        cidr_blocks     = ["0.0.0.0/0"]
    }

    ingress {
        from_port       = 22
        to_port         = 22
        protocol        = "tcp"
        cidr_blocks     = ["0.0.0.0/0"]
    }

    egress {
        from_port       = 0
        to_port         = 65535
        protocol        = "tcp"
        cidr_blocks     = ["0.0.0.0/0"]
    }
}
resource "aws_instance" "panda" {
  count                     = 2
  ami                       = "ami-0885b1f6bd170450c"
  instance_type             = "t2.micro"
  availability_zone         = var.ec2_availability_zone
  key_name                  = var.aws_key_name
  vpc_security_group_ids    = [aws_security_group.sg-pub.id]
  subnet_id = aws_subnet.pub_subnet.id

  connection {
    host        = self.public_ip
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.ssh_key_path)
  }
}

resource "aws_elb" "panda" {
  name               = "panda-load-balancer"
  security_groups   = [aws_security_group.sg-pub.id]
  subnets = [aws_subnet.pub_subnet.id]

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    target              = "HTTP:8080/"
  }

  listener {
    lb_port           = 80
    lb_protocol       = "http"
    instance_port     = "8080"
    instance_protocol = "http"
  }

  instances = aws_instance.panda.*.id
}

resource "local_file" "ansible_inventory" {
  content = templatefile("inventory.tpl", 
                        { ansible_ip = "${join("\n", aws_instance.panda.*.public_ip)}" })
  filename = "${path.module}/../ansible/inventory"
}

output "elb_dns_name" {
  value = aws_elb.panda.dns_name
}

