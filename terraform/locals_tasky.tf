locals {
  // URL-encode the app password so the URI is valid.
  mongo_app_password_uri = urlencode(random_password.mongo_app.result)
  // Use the private Route53 hostname for Mongo.
  mongo_host = aws_route53_record.mongo.fqdn

  // Connection string consumed by the Kubernetes secret.
  // Use authSource=admin because the user is created in the admin DB.
  // Database name "go-mongodb" matches the app's default.
  mongo_uri = "mongodb://tasky:${local.mongo_app_password_uri}@${local.mongo_host}:27017/go-mongodb?authSource=admin"
}
