#!/bin/bash
# ─── setup-new-infra.sh ─────────────────────────────────────────────────────
#
# Lance depuis ~/levpn :
#   chmod +x setup-new-infra.sh && ./setup-new-infra.sh
#
# Ce script :
#   1. Backup l'ancien infra/main.tf
#   2. Crée toute la nouvelle structure Terraform + scripts
#   3. Ne touche PAS au code Go existant (internal/tunnel/tunnel.go)
#   4. Met à jour cmd/server/main.go pour les cert paths certbot
#
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# Vérifier qu'on est dans ~/levpn
if [ ! -d "cmd/server" ] || [ ! -d "internal/tunnel" ]; then
  echo "Erreur : lance ce script depuis ~/levpn"
  exit 1
fi

echo "╔══════════════════════════════════════════════════════╗"
echo "║  Setup nouvelle infrastructure levpn                ║"
echo "╚══════════════════════════════════════════════════════╝"

# ── Backup ───────────────────────────────────────────────────────────────────

if [ -f "infra/main.tf" ]; then
  cp infra/main.tf infra/main.tf.old
  echo "✓ Backup : infra/main.tf → infra/main.tf.old"
fi

# ── Créer la structure ───────────────────────────────────────────────────────

mkdir -p infra/modules/tunnel-node
mkdir -p scripts
echo "✓ Dossiers créés"

# ═════════════════════════════════════════════════════════════════════════════
# TERRAFORM — MODULE tunnel-node
# ═════════════════════════════════════════════════════════════════════════════

# ── Module : variables.tf ────────────────────────────────────────────────────

cat > infra/modules/tunnel-node/variables.tf << 'ENDOFFILE'
variable "region_name" {
  description = "Identifiant court de la région (us, eu, asia, sa)"
  type        = string
}

variable "subdomain" {
  description = "Sous-domaine pour cette région (ex: us → us.aguenonnvpn.com)"
  type        = string
}

variable "zone_id" {
  description = "ID de la hosted zone Route 53"
  type        = string
}

variable "public_key_path" {
  description = "Chemin vers la clé publique SSH"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "private_key_path" {
  description = "Chemin vers la clé privée SSH"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "levpn_password" {
  description = "Mot de passe Basic Auth du proxy"
  type        = string
  sensitive   = true
}

variable "server_binary" {
  description = "Chemin local vers le binaire server-linux compilé"
  type        = string
  default     = "../server-linux"
}

variable "instance_type" {
  description = "Type d'instance EC2"
  type        = string
  default     = "t3.micro"
}

variable "contact_email" {
  description = "Email pour Let's Encrypt (certbot)"
  type        = string
  default     = "levpn@aguenonnvpn.com"
}
ENDOFFILE

# ── Module : main.tf ────────────────────────────────────────────────────────

cat > infra/modules/tunnel-node/main.tf << 'ENDOFFILE'
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
ENDOFFILE

# ── Module : outputs.tf ─────────────────────────────────────────────────────

cat > infra/modules/tunnel-node/outputs.tf << 'ENDOFFILE'
output "public_ip" {
  description = "Elastic IP du nœud"
  value       = aws_eip.levpn.public_ip
}

output "instance_id" {
  description = "ID de l'instance EC2"
  value       = aws_instance.levpn.id
}

output "domain" {
  description = "FQDN du nœud"
  value       = local.domain
}

output "pac_url" {
  description = "URL du PAC file pour cette région"
  value       = "https://aguenonnvpn.com/pac/proxy-${var.region_name}.pac"
}
ENDOFFILE

echo "✓ Module tunnel-node créé"

# ═════════════════════════════════════════════════════════════════════════════
# TERRAFORM — ROOT
# ═════════════════════════════════════════════════════════════════════════════

# ── Root : variables.tf ──────────────────────────────────────────────────────

cat > infra/variables.tf << 'ENDOFFILE'
variable "enable_us" {
  description = "Activer le nœud US (us-east-1)"
  type        = bool
  default     = true
}

variable "enable_eu" {
  description = "Activer le nœud EU (eu-west-1)"
  type        = bool
  default     = true
}

variable "enable_asia" {
  description = "Activer le nœud Asia (ap-southeast-1)"
  type        = bool
  default     = false
}

variable "enable_sa" {
  description = "Activer le nœud SA (sa-east-1)"
  type        = bool
  default     = false
}

variable "levpn_password" {
  description = "Mot de passe Basic Auth du proxy (NE JAMAIS COMMITTER)"
  type        = string
  sensitive   = true
}

variable "public_key_path" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "private_key_path" {
  type    = string
  default = "~/.ssh/id_rsa"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "server_binary" {
  type    = string
  default = "../server-linux"
}

variable "portal_bucket" {
  type    = string
  default = "aguenonnvpn-portal"
}

variable "contact_email" {
  type    = string
  default = "levpn@aguenonnvpn.com"
}
ENDOFFILE

# ── Root : main.tf ───────────────────────────────────────────────────────────

cat > infra/main.tf << 'ENDOFFILE'
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
  region = "us-east-1"
}

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

# ─── Route 53 zone ──────────────────────────────────────────────────────────

data "aws_route53_zone" "main" {
  name         = "aguenonnvpn.com"
  private_zone = false
}

# ─── Locals ──────────────────────────────────────────────────────────────────

locals {
  shared = {
    zone_id          = data.aws_route53_zone.main.zone_id
    public_key_path  = var.public_key_path
    private_key_path = var.private_key_path
    levpn_password   = var.levpn_password
    server_binary    = var.server_binary
    instance_type    = var.instance_type
    contact_email    = var.contact_email
  }
}

# ─── Module calls ────────────────────────────────────────────────────────────

module "tunnel_us" {
  source    = "./modules/tunnel-node"
  count     = var.enable_us ? 1 : 0
  providers = { aws = aws.us }

  region_name      = "us"
  subdomain        = "us"
  zone_id          = local.shared.zone_id
  public_key_path  = local.shared.public_key_path
  private_key_path = local.shared.private_key_path
  levpn_password   = local.shared.levpn_password
  server_binary    = local.shared.server_binary
  instance_type    = local.shared.instance_type
  contact_email    = local.shared.contact_email
}

module "tunnel_eu" {
  source    = "./modules/tunnel-node"
  count     = var.enable_eu ? 1 : 0
  providers = { aws = aws.eu }

  region_name      = "eu"
  subdomain        = "eu"
  zone_id          = local.shared.zone_id
  public_key_path  = local.shared.public_key_path
  private_key_path = local.shared.private_key_path
  levpn_password   = local.shared.levpn_password
  server_binary    = local.shared.server_binary
  instance_type    = local.shared.instance_type
  contact_email    = local.shared.contact_email
}

module "tunnel_asia" {
  source    = "./modules/tunnel-node"
  count     = var.enable_asia ? 1 : 0
  providers = { aws = aws.asia }

  region_name      = "asia"
  subdomain        = "asia"
  zone_id          = local.shared.zone_id
  public_key_path  = local.shared.public_key_path
  private_key_path = local.shared.private_key_path
  levpn_password   = local.shared.levpn_password
  server_binary    = local.shared.server_binary
  instance_type    = local.shared.instance_type
  contact_email    = local.shared.contact_email
}

module "tunnel_sa" {
  source    = "./modules/tunnel-node"
  count     = var.enable_sa ? 1 : 0
  providers = { aws = aws.sa }

  region_name      = "sa"
  subdomain        = "sa"
  zone_id          = local.shared.zone_id
  public_key_path  = local.shared.public_key_path
  private_key_path = local.shared.private_key_path
  levpn_password   = local.shared.levpn_password
  server_binary    = local.shared.server_binary
  instance_type    = local.shared.instance_type
  contact_email    = local.shared.contact_email
}

# ─── PAC files → S3 ─────────────────────────────────────────────────────────

resource "aws_s3_object" "pac_us" {
  count        = var.enable_us ? 1 : 0
  bucket       = var.portal_bucket
  key          = "pac/proxy-us.pac"
  content      = "function FindProxyForURL(url, host) { return \"PROXY us.aguenonnvpn.com:8080\"; }"
  content_type = "application/x-ns-proxy-autoconfig"
}

resource "aws_s3_object" "pac_eu" {
  count        = var.enable_eu ? 1 : 0
  bucket       = var.portal_bucket
  key          = "pac/proxy-eu.pac"
  content      = "function FindProxyForURL(url, host) { return \"PROXY eu.aguenonnvpn.com:8080\"; }"
  content_type = "application/x-ns-proxy-autoconfig"
}

resource "aws_s3_object" "pac_asia" {
  count        = var.enable_asia ? 1 : 0
  bucket       = var.portal_bucket
  key          = "pac/proxy-asia.pac"
  content      = "function FindProxyForURL(url, host) { return \"PROXY asia.aguenonnvpn.com:8080\"; }"
  content_type = "application/x-ns-proxy-autoconfig"
}

resource "aws_s3_object" "pac_sa" {
  count        = var.enable_sa ? 1 : 0
  bucket       = var.portal_bucket
  key          = "pac/proxy-sa.pac"
  content      = "function FindProxyForURL(url, host) { return \"PROXY sa.aguenonnvpn.com:8080\"; }"
  content_type = "application/x-ns-proxy-autoconfig"
}
ENDOFFILE

# ── Root : outputs.tf ────────────────────────────────────────────────────────

cat > infra/outputs.tf << 'ENDOFFILE'
output "us" {
  description = "Nœud US"
  value = var.enable_us ? {
    ip      = module.tunnel_us[0].public_ip
    domain  = module.tunnel_us[0].domain
    pac_url = module.tunnel_us[0].pac_url
  } : null
}

output "eu" {
  description = "Nœud EU"
  value = var.enable_eu ? {
    ip      = module.tunnel_eu[0].public_ip
    domain  = module.tunnel_eu[0].domain
    pac_url = module.tunnel_eu[0].pac_url
  } : null
}

output "asia" {
  description = "Nœud Asia"
  value = var.enable_asia ? {
    ip      = module.tunnel_asia[0].public_ip
    domain  = module.tunnel_asia[0].domain
    pac_url = module.tunnel_asia[0].pac_url
  } : null
}

output "sa" {
  description = "Nœud SA"
  value = var.enable_sa ? {
    ip      = module.tunnel_sa[0].public_ip
    domain  = module.tunnel_sa[0].domain
    pac_url = module.tunnel_sa[0].pac_url
  } : null
}

output "active_regions" {
  description = "Liste des régions actives"
  value = compact([
    var.enable_us ? "us" : "",
    var.enable_eu ? "eu" : "",
    var.enable_asia ? "asia" : "",
    var.enable_sa ? "sa" : "",
  ])
}
ENDOFFILE

# ── Root : terraform.tfvars.example ──────────────────────────────────────────

cat > infra/terraform.tfvars.example << 'ENDOFFILE'
# Copier : cp terraform.tfvars.example terraform.tfvars
# NE JAMAIS COMMITTER terraform.tfvars

enable_us   = true
enable_eu   = true
enable_asia = false
enable_sa   = false

levpn_password = "CHANGE_ME"

public_key_path  = "~/.ssh/id_rsa.pub"
private_key_path = "~/.ssh/id_rsa"
instance_type    = "t3.micro"
contact_email    = "levpn@aguenonnvpn.com"
ENDOFFILE

echo "✓ Terraform root créé"

# ═════════════════════════════════════════════════════════════════════════════
# SCRIPTS
# ═════════════════════════════════════════════════════════════════════════════

# ── up.sh ────────────────────────────────────────────────────────────────────

cat > scripts/up.sh << 'ENDOFFILE'
#!/bin/bash
set -euo pipefail

REGION="${1:-}"
VALID_REGIONS="us eu asia sa"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
INFRA_DIR="$PROJECT_DIR/infra"
TFVARS="$INFRA_DIR/terraform.tfvars"
CLOUDFRONT_ID="E27KNKKU5CUFYT"

if [ -z "$REGION" ]; then
  echo "Usage: $0 <region>"
  echo "Régions valides : $VALID_REGIONS"
  exit 1
fi

if ! echo "$VALID_REGIONS" | grep -qw "$REGION"; then
  echo "Erreur : région '$REGION' invalide."
  exit 1
fi

if [ ! -f "$TFVARS" ]; then
  echo "Erreur : $TFVARS introuvable. cp terraform.tfvars.example terraform.tfvars"
  exit 1
fi

CURRENT=$(grep "enable_${REGION}" "$TFVARS" | grep -o 'true\|false')
if [ "$CURRENT" = "true" ]; then
  echo "La région $REGION est déjà active."
  exit 0
fi

echo "╔══════════════════════════════════════╗"
echo "║  Activation région : $REGION"
echo "╚══════════════════════════════════════╝"

if [ ! -f "$PROJECT_DIR/server-linux" ]; then
  echo "→ server-linux introuvable, compilation..."
  cd "$PROJECT_DIR"
  GOOS=linux GOARCH=amd64 go build -o server-linux ./cmd/server/
  echo "✓ server-linux compilé"
fi

sed -i "s/enable_${REGION} *= *false/enable_${REGION} = true/" "$TFVARS"
echo "✓ enable_${REGION} = true"

cd "$INFRA_DIR"
echo "→ terraform apply..."
terraform apply -auto-approve

echo "→ Invalidation CloudFront..."
aws cloudfront create-invalidation \
  --distribution-id "$CLOUDFRONT_ID" \
  --paths "/pac/proxy-${REGION}.pac" \
  --output text --query 'Invalidation.Id' 2>/dev/null || true

echo ""
echo "✓ Région $REGION activée."
grep "enable_" "$TFVARS" | grep "true" | sed 's/enable_/  ✓ /' | sed 's/ *= *true//'
ENDOFFILE

# ── down.sh ──────────────────────────────────────────────────────────────────

cat > scripts/down.sh << 'ENDOFFILE'
#!/bin/bash
set -euo pipefail

REGION="${1:-}"
VALID_REGIONS="us eu asia sa"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/../infra"
TFVARS="$INFRA_DIR/terraform.tfvars"
CLOUDFRONT_ID="E27KNKKU5CUFYT"

if [ -z "$REGION" ]; then
  echo "Usage: $0 <region>"
  echo "Régions valides : $VALID_REGIONS"
  exit 1
fi

if ! echo "$VALID_REGIONS" | grep -qw "$REGION"; then
  echo "Erreur : région '$REGION' invalide."
  exit 1
fi

if [ ! -f "$TFVARS" ]; then
  echo "Erreur : $TFVARS introuvable."
  exit 1
fi

CURRENT=$(grep "enable_${REGION}" "$TFVARS" | grep -o 'true\|false')
if [ "$CURRENT" = "false" ]; then
  echo "La région $REGION est déjà désactivée."
  exit 0
fi

echo "╔══════════════════════════════════════╗"
echo "║  Désactivation région : $REGION"
echo "╚══════════════════════════════════════╝"

sed -i "s/enable_${REGION} *= *true/enable_${REGION} = false/" "$TFVARS"
echo "✓ enable_${REGION} = false"

cd "$INFRA_DIR"
echo "→ terraform apply..."
terraform apply -auto-approve

echo "→ Invalidation CloudFront..."
aws cloudfront create-invalidation \
  --distribution-id "$CLOUDFRONT_ID" \
  --paths "/pac/proxy-${REGION}.pac" \
  --output text --query 'Invalidation.Id' 2>/dev/null || true

echo ""
echo "✓ Région $REGION désactivée."
grep "enable_" "$TFVARS" | grep "true" | sed 's/enable_/  ✓ /' | sed 's/ *= *true//'
ENDOFFILE

# ── deploy-server.sh ─────────────────────────────────────────────────────────

cat > scripts/deploy-server.sh << 'ENDOFFILE'
#!/bin/bash
set -euo pipefail

TARGET="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
INFRA_DIR="$PROJECT_DIR/infra"
KEY="$HOME/.ssh/id_rsa"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i $KEY"

echo "→ Compilation server-linux..."
cd "$PROJECT_DIR"
GOOS=linux GOARCH=amd64 go build -o server-linux ./cmd/server/
echo "✓ Compilé"

cd "$INFRA_DIR"
declare -A NODES

for region in us eu asia sa; do
  IP=$(terraform output -json "${region}" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['ip'] if d else '')" 2>/dev/null || echo "")
  [ -n "$IP" ] && NODES["$region"]="$IP"
done

if [ ${#NODES[@]} -eq 0 ]; then
  echo "Aucune région active."
  exit 1
fi

if [ "$TARGET" != "all" ]; then
  if [ -z "${NODES[$TARGET]:-}" ]; then
    echo "Erreur : région '$TARGET' non active."
    exit 1
  fi
  IP="${NODES[$TARGET]}"
  unset NODES
  declare -A NODES
  NODES["$TARGET"]="$IP"
fi

for region in "${!NODES[@]}"; do
  IP="${NODES[$region]}"
  echo "── $region ($IP) ──"
  ssh $SSH_OPTS "ubuntu@$IP" "sudo systemctl stop levpn" 2>/dev/null || true
  scp $SSH_OPTS "$PROJECT_DIR/server-linux" "ubuntu@$IP:/home/ubuntu/server"
  ssh $SSH_OPTS "ubuntu@$IP" "chmod +x /home/ubuntu/server && sudo systemctl start levpn"
  echo "  ✓ OK"
done
ENDOFFILE

# ── status.sh ────────────────────────────────────────────────────────────────

cat > scripts/status.sh << 'ENDOFFILE'
#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TFVARS="$SCRIPT_DIR/../infra/terraform.tfvars"

if [ ! -f "$TFVARS" ]; then
  echo "Erreur : $TFVARS introuvable."
  exit 1
fi

LEVPN_PASSWORD=$(grep "levpn_password" "$TFVARS" | sed 's/.*= *"//' | sed 's/".*//')

echo "╔══════════════════════════════════════════════════════════╗"
echo "║                    levpn — Status                       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

for region in us eu asia sa; do
  ENABLED=$(grep "enable_${region}" "$TFVARS" 2>/dev/null | grep -o 'true\|false' || echo "unknown")

  if [ "$ENABLED" != "true" ]; then
    printf "  %-6s │ OFF\n" "$region"
    continue
  fi

  DOMAIN="${region}.aguenonnvpn.com"

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
    --proxytunnel -x "http://${DOMAIN}:8080" \
    --proxy-user "levpn:${LEVPN_PASSWORD}" \
    https://ipinfo.io/json 2>/dev/null || echo "000")

  if [ "$HTTP_CODE" = "200" ]; then
    EXIT_IP=$(curl -s --max-time 5 \
      --proxytunnel -x "http://${DOMAIN}:8080" \
      --proxy-user "levpn:${LEVPN_PASSWORD}" \
      https://ipinfo.io/json 2>/dev/null \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('ip','?'))" 2>/dev/null || echo "?")
    printf "  %-6s │ ✓  │ IP: %s\n" "$region" "$EXIT_IP"
  else
    printf "  %-6s │ ✗  │ HTTP %s\n" "$region" "$HTTP_CODE"
  fi
done

echo ""
ENDOFFILE

chmod +x scripts/*.sh
echo "✓ Scripts créés (up.sh, down.sh, deploy-server.sh, status.sh)"

# ═════════════════════════════════════════════════════════════════════════════
# cmd/server/main.go — Mise à jour cert paths
# ═════════════════════════════════════════════════════════════════════════════

cat > cmd/server/main.go << 'ENDOFFILE'
package main

import (
	"crypto/tls"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"

	"github.com/aguenonn/levpn/internal/tunnel"
)

type proxyHandler struct{}

func (p *proxyHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodConnect {
		tunnel.Handler(w, r)
		return
	}
	w.Write([]byte("OK"))
}

func main() {
	handler := &proxyHandler{}

	// Port 8080 — HTTP plain (navigateurs via PAC)
	go func() {
		log.Println("HTTP proxy listening on :8080")
		if err := http.ListenAndServe(":8080", handler); err != nil {
			log.Printf("HTTP :8080 error: %v", err)
		}
	}()

	// Port 443 — HTTPS TLS
	certFile, keyFile := getCertPaths()
	log.Printf("TLS certs: %s, %s", certFile, keyFile)

	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		log.Printf("TLS certs not found (%v) — port 8080 only", err)
		select {}
	}

	tlsConfig := &tls.Config{Certificates: []tls.Certificate{cert}}
	listener, err := tls.Listen("tcp", ":443", tlsConfig)
	if err != nil {
		log.Fatalf("TLS listen error: %v", err)
	}
	defer listener.Close()

	log.Println("HTTPS proxy listening on :443")

	for {
		conn, err := listener.Accept()
		if err != nil {
			log.Printf("accept error: %v", err)
			continue
		}
		go handleTLSConn(conn, handler)
	}
}

func handleTLSConn(conn net.Conn, handler http.Handler) {
	defer conn.Close()
	http.Serve(&singleConnListener{conn: conn}, handler)
}

type singleConnListener struct {
	conn   net.Conn
	served bool
}

func (l *singleConnListener) Accept() (net.Conn, error) {
	if l.served {
		return nil, fmt.Errorf("done")
	}
	l.served = true
	return l.conn, nil
}

func (l *singleConnListener) Close() error   { return nil }
func (l *singleConnListener) Addr() net.Addr { return l.conn.LocalAddr() }

func getCertPaths() (string, string) {
	certFile := os.Getenv("LEVPN_CERT_FILE")
	keyFile := os.Getenv("LEVPN_KEY_FILE")
	if certFile != "" && keyFile != "" {
		return certFile, keyFile
	}

	region := os.Getenv("LEVPN_REGION")
	if region == "" {
		region = "us"
	}
	domain := region + ".aguenonnvpn.com"
	return fmt.Sprintf("/etc/letsencrypt/live/%s/fullchain.pem", domain),
		fmt.Sprintf("/etc/letsencrypt/live/%s/privkey.pem", domain)
}
ENDOFFILE

echo "✓ cmd/server/main.go mis à jour"

# ═════════════════════════════════════════════════════════════════════════════
# RÉSUMÉ
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "══════════════════════════════════════════════════════════"
echo "  Setup terminé. Prochaines étapes :"
echo ""
echo "  1. Détruire l'ancienne infra :"
echo "     cd ~/levpn/infra && terraform destroy"
echo ""
echo "  2. Créer terraform.tfvars :"
echo "     cp terraform.tfvars.example terraform.tfvars"
echo "     nano terraform.tfvars  # mettre ton mot de passe"
echo ""
echo "  3. Compiler le server :"
echo "     cd ~/levpn && GOOS=linux GOARCH=amd64 go build -o server-linux ./cmd/server/"
echo ""
echo "  4. Init + Apply :"
echo "     cd infra && terraform init && terraform apply"
echo ""
echo "  5. Vérifier :"
echo "     ./scripts/status.sh"
echo "══════════════════════════════════════════════════════════"
