data "aws_iam_policy_document" "worker" {
  statement {
    actions = [
      "ec2:Describe*"
    ]

    effect    = "Allow"
    resources = ["*"]
  }
}

resource "aws_iam_role" "worker" {
  name               = "${local.cluster_id}-worker-role"
  assume_role_policy = "${data.aws_iam_policy_document.ec2.json}"

  lifecycle {
    ignore_changes = ["tags"]
  }
}

resource "aws_iam_role_policy" "worker" {
  name   = "${local.cluster_id}-worker-policy"
  role   = "${aws_iam_role.worker.id}"
  policy = "${data.aws_iam_policy_document.worker.json}"
}

resource "aws_iam_instance_profile" "worker" {
  name = "${local.cluster_id}-worker-profile"
  role = "${aws_iam_role.worker.name}"
}
