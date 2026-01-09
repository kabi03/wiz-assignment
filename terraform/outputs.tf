output "ecr_repo_url" {
  value = aws_ecr_repository.app.repository_url
}

output "mongo_public_ip" {
  value = aws_instance.mongo.public_ip
}

output "mongo_private_ip" {
  value = aws_instance.mongo.private_ip
}

output "mongo_hostname" {
  value = aws_route53_record.mongo.fqdn
}

output "mongo_uri" {
  value     = local.mongo_uri
  sensitive = true
}

output "tasky_ingress_hostname" {
  value = try(kubernetes_ingress_v1.tasky.status[0].load_balancer[0].ingress[0].hostname, null)
}

output "ssh_private_key_pem" {
  description = "Private SSH key for Mongo EC2 instance"
  value       = tls_private_key.ssh.private_key_pem
  sensitive   = true
}
