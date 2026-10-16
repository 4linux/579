output "okd_project_id" { value = google_project.okd.project_id }
output "bastion_public_ip" { value = google_compute_address.bastion.address }
output "dns_name_servers" { value = google_dns_managed_zone.lab.name_servers }
output "dns_zone" { value = google_dns_managed_zone.lab.name }
output "connect_bastion" { value = "gcloud compute ssh bastion-host --project=${var.initial_project_id} --zone=${var.zone} --tunnel-through-iap" }
output "install_command" { value = "bash scripts/deploy.sh" }

output "nip_base_domain" { value = "${replace(google_compute_address.bastion.address, ".", "-")}.nip.io" }
output "console_expected_url" { value = "https://console-openshift-console.apps.${var.cluster_name}.${replace(google_compute_address.bastion.address, ".", "-")}.nip.io" }

output "initial_project_id" { value = var.initial_project_id }
output "region" { value = var.region }
output "zone" { value = var.zone }
output "release" { value = var.release }
output "master_machine_type" { value = var.master_machine_type }
output "cluster_name" { value = var.cluster_name }
