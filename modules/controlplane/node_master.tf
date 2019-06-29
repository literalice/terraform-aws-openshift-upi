data "template_file" "master_init" {
  template = "${file("${path.module}/resources/master-init.json")}"

  vars = {
    cluster_domain = local.cluster_domain
    ca_bundle      = local.ca_bundle
  }
}

resource "aws_instance" "master" {
  count = local.count

  ami = data.aws_ami.rhcos.image_id

  instance_type = local.instance_type

  key_name = local.key_name

  associate_public_ip_address = true
  subnet_id                   = element(local.subnet_ids, count.index)
  user_data                   = base64encode(data.template_file.master_init.rendered)

  vpc_security_group_ids = local.sg_ids

  iam_instance_profile = aws_iam_instance_profile.master.name

  tags = merge({
    Name = "${local.cluster_id}-master"
    Role = "master"
  }, local.cluster_tag)


  root_block_device {
    volume_type = "gp2"
    volume_size = 32
  }

  lifecycle {
    ignore_changes = ["tags"]
  }
}

resource "aws_lb_target_group_attachment" "api" {
  count = length(aws_instance.master)
  target_group_arn = local.api_target_group_arn
  target_id = aws_instance.master[count.index].id
}

resource "aws_elb_attachment" "private_api" {
  count = length(aws_instance.master)
  elb      = local.private_api_elb_id
  instance = aws_instance.master[count.index].id
}
