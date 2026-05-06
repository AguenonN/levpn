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
