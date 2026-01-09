resource "aws_route53_zone" "tasky_internal" {
  name = "tasky.internal"

  vpc {
    vpc_id = aws_vpc.this.id
  }
}

resource "aws_route53_record" "mongo" {
  zone_id = aws_route53_zone.tasky_internal.zone_id
  name    = "mongo.tasky.internal"
  type    = "A"
  ttl     = 60
  records = [aws_instance.mongo.private_ip]
}
