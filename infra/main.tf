terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ─── Providers ───────────────────────────────────────────────────────────────

provider "aws" {
  alias  = "us"
  region = "us-east-1"
}

provider "aws" {
  alias  = "eu"
  region = "eu-west-1"
}

provider "aws" {
  alias  = "asia"
  region = "ap-southeast-1"
}

provider "aws" {
  alias  = "sa"
  region = "sa-east-1"
}

# ─── Variables ───────────────────────────────────────────────────────────────

variable "public_key_path" {
  default = "~/.ssh/id_rsa.pub"
}

# ─── Data sources : EC2 US existant ──────────────────────────────────────────

data "aws_instance" "levpn_us" {
  provider = aws.us
  filter {
    name   = "tag:Name"
    values = ["openvpn-us-east-1"]
  }
}

data "aws_eip" "levpn_us" {
  provider = aws.us
  filter {
    name   = "instance-id"
    values = [data.aws_instance.levpn_us.id]
  }
}

# ─── AMI Ubuntu 22.04 ────────────────────────────────────────────────────────

data "aws_ami" "ubuntu_eu" {
  provider    = aws.eu
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "ubuntu_asia" {
  provider    = aws.asia
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "ubuntu_sa" {
  provider    = aws.sa
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ─── Key Pairs ───────────────────────────────────────────────────────────────

resource "aws_key_pair" "levpn_eu" {
  provider   = aws.eu
  key_name   = "levpn-key"
  public_key = file(var.public_key_path)
}

resource "aws_key_pair" "levpn_asia" {
  provider   = aws.asia
  key_name   = "levpn-key"
  public_key = file(var.public_key_path)
}

resource "aws_key_pair" "levpn_sa" {
  provider   = aws.sa
  key_name   = "levpn-key"
  public_key = file(var.public_key_path)
}

# ─── Security Groups ─────────────────────────────────────────────────────────

resource "aws_security_group" "levpn_eu" {
  provider    = aws.eu
  name        = "levpn-sg"
  description = "levpn tunnel server"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "levpn_asia" {
  provider    = aws.asia
  name        = "levpn-sg"
  description = "levpn tunnel server"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "levpn_sa" {
  provider    = aws.sa
  name        = "levpn-sg"
  description = "levpn tunnel server"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ─── EC2 Instances ───────────────────────────────────────────────────────────

resource "aws_instance" "levpn_eu" {
  provider                    = aws.eu
  ami                         = data.aws_ami.ubuntu_eu.id
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.levpn_eu.key_name
  vpc_security_group_ids      = [aws_security_group.levpn_eu.id]
  associate_public_ip_address = true

  tags = {
    Name = "levpn-eu-west-1"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    host        = self.public_ip
  }

  provisioner "file" {
    source      = "../server-linux"
    destination = "/home/ubuntu/server"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/server",
      "nohup /home/ubuntu/server > /home/ubuntu/server.log 2>&1 &",
    ]
  }
}

resource "aws_instance" "levpn_asia" {
  provider                    = aws.asia
  ami                         = data.aws_ami.ubuntu_asia.id
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.levpn_asia.key_name
  vpc_security_group_ids      = [aws_security_group.levpn_asia.id]
  associate_public_ip_address = true

  tags = {
    Name = "levpn-ap-southeast-1"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    host        = self.public_ip
  }

  provisioner "file" {
    source      = "../server-linux"
    destination = "/home/ubuntu/server"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/server",
      "nohup /home/ubuntu/server > /home/ubuntu/server.log 2>&1 &",
    ]
  }
}

resource "aws_instance" "levpn_sa" {
  provider                    = aws.sa
  ami                         = data.aws_ami.ubuntu_sa.id
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.levpn_sa.key_name
  vpc_security_group_ids      = [aws_security_group.levpn_sa.id]
  associate_public_ip_address = true

  tags = {
    Name = "levpn-sa-east-1"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    host        = self.public_ip
  }

  provisioner "file" {
    source      = "../server-linux"
    destination = "/home/ubuntu/server"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/server",
      "nohup /home/ubuntu/server > /home/ubuntu/server.log 2>&1 &",
    ]
  }
}

# ─── Elastic IPs ─────────────────────────────────────────────────────────────

resource "aws_eip" "levpn_eu" {
  provider = aws.eu
  instance = aws_instance.levpn_eu.id
  domain   = "vpc"
}

resource "aws_eip" "levpn_asia" {
  provider = aws.asia
  instance = aws_instance.levpn_asia.id
  domain   = "vpc"
}

resource "aws_eip" "levpn_sa" {
  provider = aws.sa
  instance = aws_instance.levpn_sa.id
  domain   = "vpc"
}

# ─── Route 53 ────────────────────────────────────────────────────────────────

resource "aws_route53_zone" "main" {
  name = "aguenonnvpn.com"
}

resource "aws_route53_record" "us" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "us.aguenonnvpn.com"
  type    = "A"
  ttl     = 300
  records = [data.aws_eip.levpn_us.public_ip]
}

resource "aws_route53_record" "eu" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "eu.aguenonnvpn.com"
  type    = "A"
  ttl     = 300
  records = [aws_eip.levpn_eu.public_ip]
}

resource "aws_route53_record" "asia" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "asia.aguenonnvpn.com"
  type    = "A"
  ttl     = 300
  records = [aws_eip.levpn_asia.public_ip]
}

resource "aws_route53_record" "sa" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "sa.aguenonnvpn.com"
  type    = "A"
  ttl     = 300
  records = [aws_eip.levpn_sa.public_ip]
}

# ─── Outputs ─────────────────────────────────────────────────────────────────

output "us_ip" {
  value = data.aws_eip.levpn_us.public_ip
}

output "eu_ip" {
  value = aws_eip.levpn_eu.public_ip
}

output "asia_ip" {
  value = aws_eip.levpn_asia.public_ip
}

output "sa_ip" {
  value = aws_eip.levpn_sa.public_ip
}
