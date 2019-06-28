output "vpc_id" {
  value = aws_vpc.cluster.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "public_sg_id" {
  value = aws_security_group.public.id
}

output "private_sg_id" {
  value = aws_security_group.private.id
}

output "api_target_group_arn" {
  value = aws_lb_target_group.api.arn
}

output "private_api_elb_id" {
  value = aws_elb.private_api.id
}
