// Outputs used for access, debugging, and CI wiring.
output "ecr_repo_url" {
  value = aws_ecr_repository.app.repository_url
}

// Public IP for SSH access to the Mongo VM.
output "mongo_public_ip" {
  value = aws_instance.mongo.public_ip
}

// Private IP used by internal clients.
output "mongo_private_ip" {
  value = aws_instance.mongo.private_ip
}

// Private DNS name for Mongo within the VPC.
output "mongo_hostname" {
  value = aws_route53_record.mongo.fqdn
}

// Mongo connection string used by the app.
output "mongo_uri" {
  value     = local.mongo_uri
  sensitive = true
}

// ALB hostname created by the Kubernetes ingress.
output "tasky_ingress_hostname" {
  // Use try() so terraform output works before ingress is ready.
  value = try(kubernetes_ingress_v1.tasky.status[0].load_balancer[0].ingress[0].hostname, null)
}

// SSH private key generated for the Mongo VM.
output "ssh_private_key_pem" {
  description = "Private SSH key for Mongo EC2 instance"
  value       = tls_private_key.ssh.private_key_pem
  sensitive   = true
}
