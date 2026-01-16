// Private hosted zone for internal service names in the VPC.
resource "aws_route53_zone" "tasky_internal" {
  name = "tasky.internal"

  // Associate the private zone with the VPC.
  vpc {
    vpc_id = aws_vpc.this.id
  }
}

// Internal DNS record pointing to the Mongo VM private IP.
resource "aws_route53_record" "mongo" {
  zone_id = aws_route53_zone.tasky_internal.zone_id
  name    = "mongo.tasky.internal"
  type    = "A"
  ttl     = 60
  // Resolve to the instance private IP.
  records = [aws_instance.mongo.private_ip]
}
