output "application_internal_ip" {
  value = google_compute_instance.application.network_interface[0].network_ip
}
output "observability_internal_ip" {
  value = google_compute_instance.observability.network_interface[0].network_ip
}
output "observability_public_ip" {
  description = "Endereco IP publico estatico da VM observability-server."
  value       = google_compute_address.observability_public.address
}
output "grafana_url" {
  value = "http://${google_compute_address.observability_public.address}:3000"
}
output "prometheus_url" {
  value = "http://${google_compute_address.observability_public.address}:9090"
}
output "alertmanager_url" {
  value = "http://${google_compute_address.observability_public.address}:9093"
}
output "ssh_commands" {
  value = {
    observability = "gcloud compute ssh observability-server --project=${var.project_id} --zone=${var.zone} --tunnel-through-iap"
    application   = "gcloud compute ssh application-server --project=${var.project_id} --zone=${var.zone} --tunnel-through-iap"
  }
}

output "application_public_ip" {
  description = "IP publico fixo da application-server."
  value       = google_compute_address.application_public.address
}
output "app_url" {
  description = "Aulas 10-12: acessivel somente apos iniciar o WordPress."
  value       = "http://${google_compute_address.application_public.address}"
}
output "otel_demo_url" {
  description = "Aula 13: mesma URL, apos parar o WordPress e iniciar a Demo."
  value       = "http://${google_compute_address.application_public.address}:8080"
}
