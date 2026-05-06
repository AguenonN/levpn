# ─── Module tunnel-node ──────────────────────────────────────────────────────
#
# Déploie un nœud tunnel complet dans une région AWS :
#   EC2 + EIP + Security Group + Key Pair + Route 53 + certbot TLS
#
# Le provisioner installe le server Go + certbot. Un null_resource séparé
# lance certbot APRÈS que le DNS pointe vers l'EIP, puis démarre le service.
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ─── AMI Ubuntu 22.04 ───────────────────────────────────────────────────────

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ─── Key Pair ────────────────────────────────────────────────────────────────

resource "aws_key_pair" "levpn" {
  key_name   = "levpn-key"
  public_key = file(var.public_key_path)
}

# ─── Security Group ─────────────────────────────────────────────────────────

resource "aws_security_group" "levpn" {
  name        = "levpn-sg"
  description = "levpn tunnel server - ${var.region_name}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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

  tags = {
    Name = "levpn-sg-${var.region_name}"
  }
}

# ─── systemd unit template ──────────────────────────────────────────────────

locals {
  domain = "${var.subdomain}.aguenonnvpn.com"

  systemd_unit = <<-UNIT
[Unit]
Description=levpn tunnel server (${var.region_name})
After=network.target

[Service]
Environment="LEVPN_PASSWORD=${var.levpn_password}"
Environment="LEVPN_REGION=${var.region_name}"
Environment="LEVPN_CERT_FILE=/etc/letsencrypt/live/${var.subdomain}.aguenonnvpn.com/fullchain.pem"
Environment="LEVPN_KEY_FILE=/etc/letsencrypt/live/${var.subdomain}.aguenonnvpn.com/privkey.pem"
ExecStart=/home/ubuntu/server
Restart=always
User=root

[Install]
WantedBy=multi-user.target
UNIT
}

# ─── EC2 Instance ────────────────────────────────────────────────────────────

resource "aws_instance" "levpn" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.levpn.key_name
  vpc_security_group_ids      = [aws_security_group.levpn.id]
  associate_public_ip_address = true

  tags = {
    Name = "levpn-${var.region_name}"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.private_key_path)
    host        = self.public_ip
  }

  provisioner "file" {
    source      = var.server_binary
    destination = "/home/ubuntu/server"
  }

  provisioner "file" {
    content     = local.systemd_unit
    destination = "/tmp/levpn.service"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/server",
      "sudo apt-get update -qq",
      "sudo apt-get install -y certbot",
      "sudo mv /tmp/levpn.service /etc/systemd/system/levpn.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable levpn",
      "echo '0 3 * * * root certbot renew --quiet --deploy-hook \"systemctl restart levpn\"' | sudo tee /etc/cron.d/levpn-cert-renew > /dev/null",
      "sudo chmod 644 /etc/cron.d/levpn-cert-renew",
    ]
  }
}

# ─── Elastic IP ──────────────────────────────────────────────────────────────

resource "aws_eip" "levpn" {
  instance = aws_instance.levpn.id
  domain   = "vpc"

  tags = {
    Name = "levpn-eip-${var.region_name}"
  }
}

# ─── Route 53 record ────────────────────────────────────────────────────────

resource "aws_route53_record" "levpn" {
  zone_id = var.zone_id
  name    = local.domain
  type    = "A"
  ttl     = 300
  records = [aws_eip.levpn.public_ip]
}

# ─── Phase 2 : certbot + démarrage (après DNS) ──────────────────────────────

resource "null_resource" "tls_setup" {
  triggers = {
    instance_id = aws_instance.levpn.id
  }

  depends_on = [aws_route53_record.levpn]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.private_key_path)
    host        = aws_eip.levpn.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for DNS propagation...'",
      "for i in $(seq 1 30); do",
      "  RESOLVED=$(dig +short ${local.domain} @8.8.8.8 2>/dev/null | head -1)",
      "  if [ \"$RESOLVED\" = \"${aws_eip.levpn.public_ip}\" ]; then",
      "    echo 'DNS OK: ${local.domain} -> ${aws_eip.levpn.public_ip}'",
      "    break",
      "  fi",
      "  echo \"Attempt $i/30 — got '$RESOLVED', expected '${aws_eip.levpn.public_ip}'\"",
      "  sleep 10",
      "done",
      "sudo certbot certonly --standalone -d ${local.domain} --non-interactive --agree-tos -m ${var.contact_email} --http-01-port 80 || echo 'certbot failed — server will run on port 8080 only'",
      "sudo systemctl start levpn",
      "echo 'levpn service started for region ${var.region_name}'",
    ]
  }
}
