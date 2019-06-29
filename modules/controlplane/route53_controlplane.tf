data "aws_route53_zone" "private" {
  name = local.cluster_domain
  private_zone = true
}

resource "aws_route53_record" "etcd_private" {
  count = length(aws_instance.master)
  zone_id = data.aws_route53_zone.private.zone_id
  name    = "etcd-${count.index}.${local.cluster_domain}"
  type    = "A"
  ttl     = "60"
  records = [aws_instance.master[count.index].private_ip]
}

resource "aws_route53_record" "etcd_private_srv" {
  zone_id = data.aws_route53_zone.private.zone_id
  name    = "_etcd-server-ssl._tcp.${local.cluster_domain}"
  type    = "SRV"
  ttl     = "60"
  records = [for i in range(length(aws_instance.master)) : "0 10 2380 etcd-${i}.${local.cluster_domain}"]
}
