module "ec2_logs" {
  source       = "git::ssh://git@gitlab.socrate.vsct.fr/terraformcentral/terraform-ec2-common-cwlog-module.git?ref=v1.0.2"
  component_id = "${local.component_id}"
  env          = "${var.env}"
}

resource "aws_cloudwatch_log_group" "ecs_agent_log" {
  name              = "/ec2/${var.env}/${local.component_id}/ecs/ecs-agent.log"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "docker_log" {
  name              = "/ec2/${var.env}/${local.component_id}/docker"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "ecs_audit_log" {
  name              = "/ec2/${var.env}/${local.component_id}/ecs/audit.log"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "ecs_init_log" {
  name              = "/ec2/${var.env}/${local.component_id}/ecs/ecs-init.log"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_metric_filter" "OOM" {
  name           = "tf-${var.env}-${var.project}-${var.cluster_name}-OOM"
  pattern        = "died due to OOM"
  log_group_name = "${aws_cloudwatch_log_group.ecs_agent_log.name}"

  metric_transformation {
    namespace = "tf-${var.env}-${var.project}-${var.cluster_name}-logmetrics"
    name      = "OOM"
    value     = "1"
  }
}
