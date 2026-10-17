locals {
  okd_apis     = toset(["compute.googleapis.com", "dns.googleapis.com", "iam.googleapis.com", "iamcredentials.googleapis.com", "cloudresourcemanager.googleapis.com", "serviceusage.googleapis.com", "storage.googleapis.com", "servicemanagement.googleapis.com", "monitoring.googleapis.com"])
  initial_apis = toset(["compute.googleapis.com", "iam.googleapis.com", "cloudresourcemanager.googleapis.com", "serviceusage.googleapis.com"])
}
resource "google_project_service" "initial" {
  for_each           = local.initial_apis
  project            = var.initial_project_id
  service            = each.value
  disable_on_destroy = false
}
resource "google_project" "okd" {
  name                = "OKD421 Lab"
  project_id          = var.okd_project_id
  billing_account     = var.billing_account
  auto_create_network = false
  deletion_policy     = "DELETE"
}
resource "google_project_service" "okd" {
  for_each           = local.okd_apis
  project            = google_project.okd.project_id
  service            = each.value
  disable_on_destroy = false
}
resource "google_compute_network" "infra" {
  project                 = var.initial_project_id
  name                    = "infra-network"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.initial]
}
resource "google_compute_subnetwork" "infra" {
  project       = var.initial_project_id
  name          = "infra-subnet"
  region        = var.region
  network       = google_compute_network.infra.id
  ip_cidr_range = "10.10.0.0/24"
}
resource "google_compute_network" "okd" {
  project                 = google_project.okd.project_id
  name                    = "okd-network"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.okd]
}
resource "google_compute_subnetwork" "master" {
  project                  = google_project.okd.project_id
  region                   = var.region
  name                     = "master-subnet"
  network                  = google_compute_network.okd.id
  ip_cidr_range            = "10.0.0.0/24"
  private_ip_google_access = true
}
resource "google_compute_subnetwork" "worker" {
  project                  = google_project.okd.project_id
  region                   = var.region
  name                     = "worker-subnet"
  network                  = google_compute_network.okd.id
  ip_cidr_range            = "10.0.1.0/24"
  private_ip_google_access = true
}
resource "google_compute_network_peering" "infra_to_okd" {
  name         = "infra-okd-peering"
  network      = google_compute_network.infra.id
  peer_network = google_compute_network.okd.id
}
resource "google_compute_network_peering" "okd_to_infra" {
  name         = "okd-infra-peering"
  network      = google_compute_network.okd.id
  peer_network = google_compute_network.infra.id
}
resource "google_compute_firewall" "iap" {
  project       = var.initial_project_id
  name          = "infra-allow-iap-ssh"
  network       = google_compute_network.infra.name
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["okd-bastion"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
resource "google_compute_firewall" "console" {
  project       = var.initial_project_id
  name          = "infra-allow-okd-console"
  network       = google_compute_network.infra.name
  source_ranges = var.console_source_ranges
  target_tags   = ["okd-bastion"]
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}
resource "google_compute_firewall" "peering_infra" {
  project       = var.initial_project_id
  name          = "infra-allow-okd"
  network       = google_compute_network.infra.name
  source_ranges = ["10.0.0.0/16"]
  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
}
resource "google_compute_firewall" "peering_okd" {
  project       = google_project.okd.project_id
  name          = "okd-allow-infra"
  network       = google_compute_network.okd.name
  source_ranges = ["10.10.0.0/24"]
  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
}
resource "google_compute_router" "infra" {
  project = var.initial_project_id
  name    = "infra-router"
  region  = var.region
  network = google_compute_network.infra.id
}
resource "google_compute_router_nat" "infra" {
  project                            = var.initial_project_id
  name                               = "infra-nat"
  region                             = var.region
  router                             = google_compute_router.infra.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
resource "google_compute_router" "okd" {
  project = google_project.okd.project_id
  name    = "okd-router"
  region  = var.region
  network = google_compute_network.okd.id
}
resource "google_compute_router_nat" "okd" {
  project                            = google_project.okd.project_id
  name                               = "okd-nat"
  region                             = var.region
  router                             = google_compute_router.okd.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
resource "google_dns_managed_zone" "lab" {
  project       = google_project.okd.project_id
  name          = "okd421-zone"
  dns_name      = "${replace(google_compute_address.bastion.address, ".", "-")}.nip.io."
  description   = "Zona do laboratorio nip.io sem delegacao publica; somente para registros internos do instalador"
  force_destroy = true
  depends_on    = [google_project_service.okd]
}
resource "google_service_account" "installer" {
  project      = google_project.okd.project_id
  account_id   = "okd-installer-lab"
  display_name = "Instalador OKD 4.21 Lab"
  depends_on   = [google_project_service.okd]
}
resource "google_project_iam_member" "installer" {
  for_each = toset(["roles/compute.admin", "roles/compute.networkAdmin", "roles/compute.securityAdmin", "roles/compute.storageAdmin", "roles/compute.loadBalancerAdmin", "roles/dns.admin", "roles/iam.serviceAccountAdmin", "roles/iam.serviceAccountUser", "roles/resourcemanager.projectIamAdmin", "roles/storage.admin", "roles/servicemanagement.quotaViewer", "roles/monitoring.viewer", "roles/resourcemanager.tagUser", "roles/iam.viewer"])
  project  = google_project.okd.project_id
  role     = each.key
  member   = "serviceAccount:${google_service_account.installer.email}"
}
resource "google_project_iam_member" "initial_viewer" {
  project = var.initial_project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.installer.email}"
}
data "google_project" "initial" {
  project_id = var.initial_project_id
}
resource "google_service_account_iam_member" "bastion_key_creator" {
  service_account_id = google_service_account.installer.name
  role               = "roles/iam.serviceAccountKeyAdmin"
  member             = "serviceAccount:${data.google_project.initial.number}-compute@developer.gserviceaccount.com"
}
resource "google_compute_address" "bastion" {
  project    = var.initial_project_id
  name       = "okd421-bastion-ip"
  region     = var.region
  depends_on = [google_project_service.initial]
}
resource "google_compute_instance" "bastion" {
  project      = var.initial_project_id
  name         = "bastion-host"
  zone         = var.zone
  machine_type = "e2-standard-2"
  tags         = ["okd-bastion"]
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 60
      type  = "pd-balanced"
    }
  }
  metadata = {
    enable-oslogin = "TRUE"

    startup-script = <<-EOF
      #!/bin/bash
      set -e

      # Atualiza a lista de pacotes e instala o NFS
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y nfs-kernel-server

      # Cria o diretório de compartilhamento
      mkdir -p /nfs
      chown nobody:nogroup /nfs
      chmod 755 /nfs

      # Configura o compartilhamento NFS
      echo '/nfs *(rw,sync,no_subtree_check,no_root_squash)' > /etc/exports.d/okd.exports

      # Aplica as configurações
      exportfs -ra

      # Habilita e inicia o servidor NFS
      systemctl enable nfs-kernel-server
      systemctl restart nfs-kernel-server
    EOF
  }

  network_interface {
    subnetwork = google_compute_subnetwork.infra.id
    access_config { nat_ip = google_compute_address.bastion.address }
  }
  service_account { scopes = ["cloud-platform"] }
  depends_on = [google_compute_router_nat.infra, google_compute_network_peering.infra_to_okd, google_compute_network_peering.okd_to_infra, google_dns_managed_zone.lab, google_service_account_iam_member.bastion_key_creator, google_project_iam_member.installer]
}
