variable "project_id" {
  description = "ID do projeto inicial (My First Project), NAO o projeto OKD."
  type = string
}
variable "region" {
  type    = string
  default = "us-central1"
}
variable "zone" {
  type    = string
  default = "us-central1-a"
}
variable "network" {
  type    = string
  default = "default"
}
variable "subnetwork" {
  type    = string
  default = "default"
}
variable "observability_disk_gb" {
  type    = number
  default = 40
}
variable "application_disk_gb" {
  type    = number
  default = 55
}
variable "disk_type" {
  type    = string
  default = "pd-balanced"
}
