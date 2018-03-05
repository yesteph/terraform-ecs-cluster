resource "aws_ecs_cluster" "cluster" {
  name = "${local.cluster_name}"

  count = "${var.env == "prod" ? 0 : 1}"
}

resource "aws_ecs_cluster" "protected_cluster" {
  name = "${local.cluster_name}"

  lifecycle {
    prevent_destroy = true
  }

  count = "${var.env == "prod" ? 1 : 0}"

  // terraform does not support conditions in lifecycle => hack https://github.com/hashicorp/terraform/issues/3116
}
