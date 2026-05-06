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
