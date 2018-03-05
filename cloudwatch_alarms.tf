resource "aws_cloudwatch_metric_alarm" "ecs_cluster_max_size_alarm" {
  alarm_name          = "${aws_autoscaling_group.ecs.name}-max-size-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "5"
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = "60"
  statistic           = "Average"
  threshold           = "${floor(aws_autoscaling_group.ecs.max_size * 0.9)}"

  dimensions {
    AutoScalingGroupName = "${aws_autoscaling_group.ecs.name}"
  }

  alarm_description = "This metric monitor capacity versus max size for autoscaling group ${aws_autoscaling_group.ecs.name}."
  alarm_actions     = ["${var.alarm_notification_topic_arn}"]

  count = "${var.enable_alarm_creation == true ? 1:0}"
}

resource "aws_cloudwatch_metric_alarm" "ecs_cluster_oom" {
  alarm_name          = "${aws_autoscaling_group.ecs.name}-OOM"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "OOM"
  namespace           = "tf-${var.env}-${var.project}-${var.cluster_name}-logmetrics"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"

  alarm_description = "This metric monitor Out of memory on ECS cluster ${var.cluster_name}."
  alarm_actions     = ["${var.alarm_notification_topic_arn}"]

  count = "${var.enable_alarm_creation == true ? 1:0}"
}

module "ec2_alarms" {
  source = "git::ssh://git@gitlab.socrate.vsct.fr/terraformcentral/terraform-ec2-common-alarms-module.git?ref=v1.1.0"

  env                          = "${var.env}"
  autoscaling_group_name       = "${aws_autoscaling_group.ecs.name}"
  alarm_notification_topic_arn = "${var.alarm_notification_topic_arn}"
  enable_alarm_creation        = "${var.enable_alarm_creation}"
}

resource "aws_cloudwatch_metric_alarm" "sfn_asg_updater_failed" {
  alarm_name          = "${aws_sfn_state_machine.asg_updater.name}-failed"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "1"

  dimensions {
    StateMachineArn = "${local.state_machine_updater_arn}"
  }

  alarm_description = "This metric monitor failures of step function ${aws_sfn_state_machine.asg_updater.name}, used to update EC2 instances in the ECS cluster ${var.cluster_name}."
  alarm_actions     = ["${var.alarm_notification_topic_arn}"]

  count = "${var.enable_alarm_creation == "true" ? 1:0}"
}

resource "aws_cloudwatch_metric_alarm" "sfn_asg_launch_failed" {
  alarm_name          = "${aws_sfn_state_machine.asg_launch.name}-failed"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "1"

  dimensions {
    StateMachineArn = "${local.state_machine_launch_arn}"
  }

  alarm_description = "This metric monitor failures of step function ${aws_sfn_state_machine.asg_launch.name}, used to ensure EC2 instances are Ok at startup in the ECS cluster ${var.cluster_name}."
  alarm_actions     = ["${var.alarm_notification_topic_arn}"]

  count = "${var.enable_alarm_creation == "true" ? 1:0}"
}
