locals {
  mongo_app_password_uri = urlencode(random_password.mongo_app.result)
  mongo_host             = aws_route53_record.mongo.fqdn

  # Keep authSource=admin because we will create user in admin DB
  mongo_uri = "mongodb://tasky:${local.mongo_app_password_uri}@${local.mongo_host}:27017/go-mongodb?authSource=admin"
}
