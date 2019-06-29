data "template_file" "bootstrap_init" {
  template = file("${path.module}/resources/bootstrap-init.json")

  vars = {
    cluster_infra_bucket = "s3://${aws_s3_bucket_object.bootstrap_ignition.bucket}/${aws_s3_bucket_object.bootstrap_ignition.key}"
  }
}

resource "aws_instance" "bootstrap" {
  ami = data.aws_ami.rhcos.image_id

  instance_type = "i3.large"

  key_name = local.key_name

  associate_public_ip_address = true
  subnet_id                   = element(local.subnet_ids, 0)
  user_data                   = base64encode(data.template_file.bootstrap_init.rendered)

  vpc_security_group_ids = local.sg_ids

  iam_instance_profile = aws_iam_instance_profile.bootstrap.name

  tags = merge({
    Name = "${local.cluster_id}-bootstrap"
    Role = "bootstrap"
  }, local.cluster_tag)

  root_block_device {
    volume_type = "gp2"
    volume_size = 32
  }

  lifecycle {
    ignore_changes = ["tags"]
  }
}

resource "aws_lb_target_group_attachment" "bootstrap_api" {
  target_group_arn = local.api_target_group_arn
  target_id        = aws_instance.bootstrap.id
}

resource "aws_elb_attachment" "private_api" {
  elb      = local.private_api_elb_id
  instance = aws_instance.bootstrap.id
}
