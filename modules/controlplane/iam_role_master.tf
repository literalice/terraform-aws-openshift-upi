data "aws_iam_policy_document" "master" {
  statement {
    actions = [
      "ec2:*",
      "elasticloadbalancing:*",
      "iam:PassRole"
    ]

    effect    = "Allow"
    resources = ["*"]
  }
}

resource "aws_iam_role" "master" {
  name               = "${local.cluster_id}-master-role"
  assume_role_policy = "${data.aws_iam_policy_document.ec2.json}"

  lifecycle {
    ignore_changes = ["tags"]
  }
}

resource "aws_iam_role_policy" "master" {
  name   = "${local.cluster_id}-master-policy"
  role   = "${aws_iam_role.master.id}"
  policy = "${data.aws_iam_policy_document.master.json}"
}

resource "aws_iam_instance_profile" "master" {
  name = "${local.cluster_id}-master-profile"
  role = "${aws_iam_role.master.name}"
}
