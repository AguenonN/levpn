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
