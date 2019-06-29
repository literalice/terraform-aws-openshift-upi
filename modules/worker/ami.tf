
data "aws_ami" "rhcos" {
  most_recent = true

  owners = ["531415883065"]

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "name"
    values = ["rhcos-410.*-hvm"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
