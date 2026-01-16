// Install the Mongo backup cron script on the VM via SSH.
resource "null_resource" "mongo_backup_cron" {
  depends_on = [aws_instance.mongo]

  // Re-run when instance, bucket, or script changes.
  triggers = {
    instance_id = aws_instance.mongo.id
    bucket      = aws_s3_bucket.public_backups.bucket
    script_sha1 = filesha1("${path.module}/scripts/mongo_backup_cron.sh")
  }

  // SSH connection to the Mongo VM.
  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = aws_instance.mongo.public_ip
    private_key = tls_private_key.ssh.private_key_pem
  }

  // Copy the cron installer script to the instance.
  provisioner "file" {
    source      = "${path.module}/scripts/mongo_backup_cron.sh"
    destination = "/tmp/mongo_backup_cron.sh"
  }

  // Execute the installer with bucket and password env vars.
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/mongo_backup_cron.sh",
      "sudo BACKUP_BUCKET='${aws_s3_bucket.public_backups.bucket}' MONGO_APP_PASSWORD='${random_password.mongo_app.result}' /tmp/mongo_backup_cron.sh",
    ]
  }
}
