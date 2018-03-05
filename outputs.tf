output "ecs_cluster_security_group_id" {
  value = "${aws_security_group.ecs_access_sg.id}"
}

output "ecs_cluster_name" {
  value = "${local.cluster_name}"
}

output "ecs_cluster_arn" {
  value = "${local.ecs_cluster_arn}"
}

output "iam_ecs_service_role_arn" {
  value = "${aws_iam_role.ecs_container_service_role.arn}"
}

output "iam_ecs_autoscale_role_arn" {
  value = "${aws_iam_role.ecs_auto_scale_role.arn}"
}

output "autoscaling_group_name" {
  description = "The name of the created autoscaling group"
  value       = "${aws_autoscaling_group.ecs.name}"
}

resource "tls_private_key" "admin_key" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

output "ami_id" {
  description = "The name of the used AMI"
  value       = "${var.ami_id == "false" ? data.aws_ami.last_ami.id : var.ami_id}"
}


data "aws_ssm_parameter" "my_db_password" {
  name  = "/sensisitve/prod/db/password/instance_01"
}


data "aws_ssm_parameter" "my_db_password" {
  name  = "${var.environment}/database/password/master"
}

resource "random_string" "password" {
  length = 16
  special = true
}

resource "aws_ssm_parameter" "my_db_password" {
  name  = "${var.environment}/database/password/master"
  type  = "SecureString"
  value = "${random_string.password.result}"
  key_id = "${var.kms_key_arn}"

  lifecycle {
    ignore_changes = ["value"]
  }
}

output "my_auto_created_tls_pkey" {
  description = "The generated private TLS key"
  value       = "${tls_private_key.admin_key.private_key_pem}"
  sensitive = true
}

