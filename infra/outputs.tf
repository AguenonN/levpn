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
