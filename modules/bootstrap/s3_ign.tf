resource "aws_s3_bucket" "ign" {
  bucket = "${local.cluster_id}-infra"
  acl    = "private"

  tags = {
    Name = "${local.cluster_id}-infra"
  }

  lifecycle {
    ignore_changes = ["tags"]
  }
}

resource "aws_s3_bucket_object" "bootstrap_ignition" {
  bucket = aws_s3_bucket.ign.bucket
  key    = "bootstrap.ign"
  source = local.ign_path

  etag = filemd5(local.ign_path)
}
