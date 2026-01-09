resource "null_resource" "mongo_backup_cron" {
  depends_on = [
    aws_instance.mongo
  ]

  triggers = {
    instance_id = aws_instance.mongo.id
    bucket      = aws_s3_bucket.public_backups.bucket
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = aws_instance.mongo.public_ip
    private_key = tls_private_key.ssh.private_key_pem
  }

  provisioner "file" {
    source      = "${path.module}/scripts/mongo_backup_cron.sh"
    destination = "/tmp/mongo_backup_cron.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/mongo_backup_cron.sh",
      "sudo MONGO_APP_PASSWORD='${random_password.mongo_app.result}' BACKUP_BUCKET='${aws_s3_bucket.public_backups.bucket}' /tmp/mongo_backup_cron.sh"
    ]
  }
}
