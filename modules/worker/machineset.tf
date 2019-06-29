data "template_file" "machineset" {
  template = file("${path.module}/resources/machinesets-worker-template.yaml")

  vars = {
    cluster_id = local.cluster_id
    worker_profile = aws_iam_instance_profile.worker.name
    az = local.availability_zones[0]
    ami = data.aws_ami.rhcos.image_id
    region = data.aws_region.current.name
  }
}

resource "null_resource" "machineset" {
  provisioner "local-exec" {
    command = "echo '${data.template_file.machineset.rendered}' | oc --config ${local.config_dir}/auth/kubeconfig apply -f -"
  }
}