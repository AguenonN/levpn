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
