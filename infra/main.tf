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

# ─── AMI Ubuntu 22.04 ────────────────────────────────────────────────────────

data "aws_ami" "ubuntu_us" {
  provider    = aws.us
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

resource "aws_key_pair" "levpn_us" {
  provider   = aws.us
  key_name   = "levpn-key"
  public_key = file(var.public_key_path)
}

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

resource "aws_security_group" "levpn_us" {
  provider    = aws.us
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

# ─── User data script ────────────────────────────────────────────────────────

locals {
  server_service = <<-EOF
    [Unit]
    Description=levpn tunnel server
    After=network.target

    [Service]
    ExecStart=/home/ubuntu/server
    Restart=always
    User=ubuntu

    [Install]
    WantedBy=multi-user.target
  EOF
}

# ─── EC2 Instances ───────────────────────────────────────────────────────────

resource "aws_instance" "levpn_us" {
  provider                    = aws.us
  ami                         = data.aws_ami.ubuntu_us.id
  instance_type               = "t3.micro"
  key_name                    = aws_key_pair.levpn_us.key_name
  vpc_security_group_ids      = [aws_security_group.levpn_us.id]
  associate_public_ip_address = true

  tags = {
    Name = "levpn-us-east-1"
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

  provisioner "file" {
    content     = local.server_service
    destination = "/tmp/levpn.service"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/server",
      "sudo mv /tmp/levpn.service /etc/systemd/system/levpn.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable levpn",
      "sudo systemctl start levpn",
    ]
  }
}

resource "aws_instance" "levpn_eu" {
  provider                    = aws.eu
  ami                         = data.aws_ami.ubuntu_eu.id
  instance_type               = "t3.micro"
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

  provisioner "file" {
    content     = local.server_service
    destination = "/tmp/levpn.service"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/server",
      "sudo mv /tmp/levpn.service /etc/systemd/system/levpn.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable levpn",
      "sudo systemctl start levpn",
    ]
  }
}

resource "aws_instance" "levpn_asia" {
  provider                    = aws.asia
  ami                         = data.aws_ami.ubuntu_asia.id
  instance_type               = "t3.micro"
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

  provisioner "file" {
    content     = local.server_service
    destination = "/tmp/levpn.service"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/server",
      "sudo mv /tmp/levpn.service /etc/systemd/system/levpn.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable levpn",
      "sudo systemctl start levpn",
    ]
  }
}

resource "aws_instance" "levpn_sa" {
  provider                    = aws.sa
  ami                         = data.aws_ami.ubuntu_sa.id
  instance_type               = "t3.micro"
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

  provisioner "file" {
    content     = local.server_service
    destination = "/tmp/levpn.service"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/server",
      "sudo mv /tmp/levpn.service /etc/systemd/system/levpn.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable levpn",
      "sudo systemctl start levpn",
    ]
  }
}

# ─── Elastic IPs ─────────────────────────────────────────────────────────────

resource "aws_eip" "levpn_us" {
  provider = aws.us
  instance = aws_instance.levpn_us.id
  domain   = "vpc"
}

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
  records = [aws_eip.levpn_us.public_ip]
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
  value = aws_eip.levpn_us.public_ip
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
