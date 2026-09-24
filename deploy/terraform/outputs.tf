output "jobs_url" {
  description = "Only /jobs is published on the host. Broker, Redis, mock, worker, and probes stay inside the cluster."
  value       = "http://127.0.0.1:8080/jobs"
}

output "grafana_port_forward" {
  description = "Grafana is ClusterIP. Leave this command running, then open the printed URL."
  value       = "kubectl -n takehome port-forward --address 127.0.0.1 svc/grafana 3000:3000"
}

output "image_tag" {
  value = var.image_tag
}
