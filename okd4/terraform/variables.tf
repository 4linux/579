variable "initial_project_id" {
  type = string
}
variable "okd_project_id" {
  type = string
}
variable "billing_account" {
  type = string
}
variable "create_service_account_key" {
  type        = bool
  default     = true
  description = "Criar chave JSON para o instalador (laboratorio)."
}
variable "region" {
  type    = string
  default = "us-central1"
}
variable "zone" {
  type    = string
  default = "us-central1-a"
}
variable "release" {
  type    = string
  default = "4.21.0-okd-scos.11"
}
variable "cluster_name" {
  type    = string
  default = "okd"
}

variable "master_machine_type" {
  type        = string
  default     = "e2-standard-8"
  description = "e2-standard-4 e experimental para SNO OKD 4.21 (minimo documentado: 8 vCPU)."
  validation {
    condition     = contains(["e2-standard-8", "e2-standard-4"], var.master_machine_type)
    error_message = "Escolha e2-standard-8 ou e2-standard-4."
  }
}
variable "console_source_ranges" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDRs autorizados ao HTTP/HTTPS do bastion; prefira seu IP/32."
}
