locals {
  base_labels = { purpose = "observabilidade", owner = "terraform" }
}
resource "google_compute_address" "observability_public" {
  name   = "observability-static-ip"
  region = var.region
}

resource "google_compute_address" "observability_private" {
  name         = "observability-private-ip"
  region       = var.region
  address_type = "INTERNAL"
  subnetwork   = var.subnetwork
}

resource "google_compute_address" "application_public" {
  name   = "application-static-ip"
  region = var.region
}

resource "google_compute_firewall" "application_web" {
  name          = "lab-application-web-public"
  network       = var.network
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["application"]

  allow {
    protocol = "tcp"
    ports    = ["80", "8080"]
  }
}

resource "google_compute_firewall" "observability_web" {
  name          = "lab-observability-web-public"
  network       = var.network
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["observability"]

  allow {
    protocol = "tcp"
    ports    = ["3000", "9090", "9093"]
  }
}

resource "google_compute_firewall" "app_exporters" {
  name          = "lab-app-exporters"
  network       = var.network
  direction     = "INGRESS"
  source_tags   = ["observability"]
  target_tags   = ["application"]
  allow {
    protocol = "tcp"
    ports    = ["9100", "9104", "9117"]
  }
}
resource "google_compute_firewall" "app_to_otel" {
  name          = "lab-app-to-otel"
  network       = var.network
  direction     = "INGRESS"
  source_tags   = ["application"]
  target_tags   = ["observability"]
  allow {
    protocol = "tcp"
    ports    = ["4317", "4318"]
  }
}
resource "google_compute_firewall" "iap_ssh" {
  name          = "lab-iap-ssh"
  network       = var.network
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["observability", "application"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
resource "google_compute_instance" "application" {
  name         = "application-server"
  machine_type = "e2-standard-4"
  zone         = var.zone
  tags         = ["application"]
  labels       = local.base_labels
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = var.application_disk_gb
      type  = var.disk_type
    }
  }
  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
    access_config {
      nat_ip = google_compute_address.application_public.address
    }
  }
  metadata = { enable-oslogin = "TRUE" }
  metadata_startup_script = templatefile("${path.module}/bootstrap/startup.sh.tftpl", {
    archive_b64 = filebase64("${path.module}/bootstrap/application.tar.gz")
    role = "application"
    application_ip = ""
    observability_ip = google_compute_address.observability_private.address
  })
  service_account { scopes = ["https://www.googleapis.com/auth/logging.write", "https://www.googleapis.com/auth/monitoring.write"] }
}
resource "google_compute_instance" "observability" {
  name         = "observability-server"
  machine_type = "e2-standard-2"
  zone         = var.zone
  tags         = ["observability"]
  labels       = local.base_labels
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = var.observability_disk_gb
      type  = var.disk_type
    }
  }
  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
    network_ip = google_compute_address.observability_private.address
    access_config {
      nat_ip = google_compute_address.observability_public.address
    }
  }
  metadata = { enable-oslogin = "TRUE" }
  metadata_startup_script = templatefile("${path.module}/bootstrap/startup.sh.tftpl", {
    archive_b64 = filebase64("${path.module}/bootstrap/observability.tar.gz")
    role = "observability"
    application_ip = google_compute_instance.application.network_interface[0].network_ip
    observability_ip = ""
  })
  service_account { scopes = ["https://www.googleapis.com/auth/logging.write", "https://www.googleapis.com/auth/monitoring.write"] }
}
