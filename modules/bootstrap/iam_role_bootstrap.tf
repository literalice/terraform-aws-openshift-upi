data "aws_iam_policy_document" "bootstrap" {
  statement {
    actions = [
      "ec2:Describe*",
      "ec2:AttachVolume",
      "ec2:DetachVolume"
    ]

    effect    = "Allow"
    resources = ["*"]
  }

  statement {
    actions = [
      "s3:GetObject"
    ]

    effect    = "Allow"
    resources = ["arn:aws:s3:::*"]
  }
}

resource "aws_iam_role" "bootstrap" {
  name               = "${local.cluster_id}-bootstrap-role"
  assume_role_policy = "${data.aws_iam_policy_document.ec2.json}"

  lifecycle {
    ignore_changes = ["tags"]
  }
}

resource "aws_iam_role_policy" "bootstrap" {
  name   = "${local.cluster_id}-bootstrap-policy"
  role   = "${aws_iam_role.bootstrap.id}"
  policy = "${data.aws_iam_policy_document.bootstrap.json}"
}

resource "aws_iam_instance_profile" "bootstrap" {
  name = "${local.cluster_id}-bootstrap-profile"
  role = "${aws_iam_role.bootstrap.name}"
}
