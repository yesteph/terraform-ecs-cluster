data "aws_caller_identity" "ami_owner" {}

data "aws_ami" "last_ami" {
  most_recent = true

  filter {
    name = "name"

    values = [
      "ecs-*",
    ]
  }

  filter {
    name = "architecture"

    values = [
      "x86_64",
    ]
  }

  filter {
    name = "tag:lifecycle"

    values = [
      "${var.ami_lifecycle_tag}",
    ]
  }

  filter {
    name = "tag:user-data-md5"

    values = [
      "${md5(data.template_file.user_data.rendered)}",
    ]
  }

  owners = ["${data.aws_caller_identity.ami_owner.account_id}"]
}

data "aws_ami" "specific_ami" {
  most_recent = true // useless data source. just create it to ensure the ami_id is existing

  filter {
    name   = "image-id"
    values = ["${var.ami_id}"]
  }

  count = "${var.ami_id == "false" ? 0:1}"
}

data "template_file" "user_data" {
  template = "${file("${path.module}/templates/user_data.tpl")}"

  vars {
    ecs_clustername = "${local.cluster_name}"
    proxy           = "${var.http_proxy}"
    component_id    = "${local.component_id}"
    env             = "${var.env}"
  }
}

resource "aws_launch_configuration" "ecs" {
  name_prefix          = "${local.component_id}-launch-config-"
  image_id             = "${var.ami_id == "false" ? data.aws_ami.last_ami.id : var.ami_id}"
  instance_type        = "${var.instance_type}"
  key_name             = "${var.ssh_key_pair}"
  iam_instance_profile = "${aws_iam_instance_profile.ecs_container_instance_profile.arn}"
  security_groups      = ["${aws_security_group.ecs_access_sg.id}"]
  ebs_optimized        = "${substr(var.instance_type, 0, 2) == "t2" ? false : true}"
  user_data            = "${data.template_file.user_data.rendered}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "ecs" {
  name                 = "${local.component_id}"
  vpc_zone_identifier  = ["${var.subnets}"]
  launch_configuration = "${aws_launch_configuration.ecs.name}"
  min_size             = "${var.autoscaling_min_size}"
  max_size             = "${var.autoscaling_max_size}"
  default_cooldown     = "180"                                  // consider 3 minutes for a newly launched instance to be Up and running

  //desired_capacity     = 1
  enabled_metrics      = ["GroupMinSize", "GroupMaxSize", "GroupDesiredCapacity", "GroupInServiceInstances", "GroupPendingInstances", "GroupStandbyInstances", "GroupTerminatingInstances", "GroupTotalInstances"]
  termination_policies = ["OldestInstance", "ClosestToNextInstanceHour"]

  lifecycle {
    create_before_destroy = true
  }

  tags = [
    {
      key                 = "cost:project"
      value               = "${var.project}"
      propagate_at_launch = true
    },
    {
      key                 = "cost:cost-center"
      value               = "${var.env == "prod" ? "prod":"dev"}"
      propagate_at_launch = true
    },
    {
      key                 = "cost:environment"
      value               = "${var.env}"
      propagate_at_launch = true
    },
    {
      key                 = "cost:component"
      value               = "ecs-cluster"
      propagate_at_launch = true
    },
    {
      key                 = "environment"
      value               = "${var.env}"
      propagate_at_launch = true
    },
    {
      key                 = "component_id"
      value               = "${local.component_id}"
      propagate_at_launch = true
    },
    {
      key                 = "ecs_cluster"
      value               = "${local.cluster_name}"
      propagate_at_launch = true
    },
  ]
}

resource "aws_autoscaling_lifecycle_hook" "terminate" {
  // we indicate the ECS cluster name in the meta-data ; used by the lambda.

  name                   = "prepare_draining"
  autoscaling_group_name = "${aws_autoscaling_group.ecs.name}"
  default_result         = "CONTINUE"                             // treat following lifecycle hooks if provided
  heartbeat_timeout      = "${var.ecs_heartbeat_timeout}"
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"

  notification_metadata = <<EOF
{
  "ecs_cluster_name": "${local.cluster_name}"
}
EOF

  notification_target_arn = "${aws_sns_topic.ec2_lifecycle_notifications.arn}"
  role_arn                = "${aws_iam_role.ecs_notification_role.arn}"
}

resource "aws_autoscaling_policy" "ecs_cluster_cpu_scale_out_policy" {
  name                      = "tf-${var.env}-${var.project}-ecs-${var.cluster_name}-cpu-scale-out-policy"
  adjustment_type           = "ChangeInCapacity"
  autoscaling_group_name    = "${aws_autoscaling_group.ecs.name}"
  policy_type               = "StepScaling"
  metric_aggregation_type   = "Average"
  estimated_instance_warmup = 200

  step_adjustment {
    metric_interval_lower_bound = 0  // +1 between 80% and 90% CPU reservation
    metric_interval_upper_bound = 10
    scaling_adjustment          = 1
  }

  step_adjustment {
    metric_interval_lower_bound = 10 // +2 above 90% CPU reservation
    scaling_adjustment          = 2
  }

  count = "${local.checked_ec2_scaling_policy != "min_max_memory_only" ? 1:0}"
}

resource "aws_cloudwatch_metric_alarm" "ecs_cluster_cpu_scale_out_alarm" {
  alarm_name          = "tf-${var.env}-${var.project}-ecs-${var.cluster_name}-cpu-scale-out-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUReservation"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "${var.scaling_cpu_max_percent}"

  dimensions {
    ClusterName = "${local.cluster_name}"
  }

  alarm_description = "This metric monitor ecs cluster cpu utilization"
  alarm_actions     = ["${aws_autoscaling_policy.ecs_cluster_cpu_scale_out_policy.arn}"]

  count = "${local.checked_ec2_scaling_policy != "min_max_memory_only" ? 1:0}"
}

resource "aws_autoscaling_policy" "ecs_cluster_memory_scale_out_policy" {
  name                      = "tf-${var.env}-${var.project}-ecs-${var.cluster_name}-memory-scale-out-policy"
  adjustment_type           = "ChangeInCapacity"
  autoscaling_group_name    = "${aws_autoscaling_group.ecs.name}"
  policy_type               = "StepScaling"
  metric_aggregation_type   = "Average"
  estimated_instance_warmup = 200

  step_adjustment {
    metric_interval_lower_bound = 0  // +1 between 80% and 90% Memory reservation
    metric_interval_upper_bound = 10
    scaling_adjustment          = 1
  }

  step_adjustment {
    metric_interval_lower_bound = 10 // +2 above 90% Memory reservation
    scaling_adjustment          = 2
  }

  count = "${local.checked_ec2_scaling_policy != "min_max_cpu_only" ? 1:0}"
}

resource "aws_cloudwatch_metric_alarm" "ecs_cluster_memory_scale_out_alarm" {
  alarm_name          = "tf-${var.env}-${var.project}-ecs-${var.cluster_name}-memory-scale-out-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "MemoryReservation"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "${var.scaling_memory_max_percent}"

  dimensions {
    ClusterName = "${local.cluster_name}"
  }

  alarm_description = "This metric monitor ecs cluster memory utilization"
  alarm_actions     = ["${aws_autoscaling_policy.ecs_cluster_memory_scale_out_policy.arn}"]

  count = "${local.checked_ec2_scaling_policy != "min_max_cpu_only" ? 1:0}"
}

resource "aws_autoscaling_policy" "ecs_cluster_cpu_scale_in_policy" {
  name                      = "tf-${var.env}-${var.project}-ecs-${var.cluster_name}-cpu-scale-in-policy"
  adjustment_type           = "ChangeInCapacity"
  autoscaling_group_name    = "${aws_autoscaling_group.ecs.name}"
  policy_type               = "StepScaling"
  metric_aggregation_type   = "Average"
  estimated_instance_warmup = 200

  step_adjustment {
    metric_interval_upper_bound = 0
    scaling_adjustment          = -1
  }

  count = "${local.checked_ec2_scaling_policy != "min_max_memory_only" ? 1:0}"
}

resource "aws_cloudwatch_metric_alarm" "ecs_cluster_cpu_scale_in_alarm" {
  alarm_name          = "tf-${var.env}-${var.project}-ecs-${var.cluster_name}-cpu-scale-in-alarm"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "5"
  metric_name         = "CPUReservation"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "${var.scaling_cpu_min_percent}"

  dimensions {
    ClusterName = "${local.cluster_name}"
  }

  alarm_description = "This metric monitor ecs cluster cpu utilization"
  alarm_actions     = ["${aws_autoscaling_policy.ecs_cluster_cpu_scale_in_policy.arn}"]

  count = "${local.checked_ec2_scaling_policy != "min_max_memory_only" ? 1:0}"
}

resource "aws_autoscaling_policy" "ecs_cluster_memory_scale_in_policy" {
  name                      = "tf-${var.env}-${var.project}-ecs-${var.cluster_name}-memory-scale-in-policy"
  adjustment_type           = "ChangeInCapacity"
  autoscaling_group_name    = "${aws_autoscaling_group.ecs.name}"
  policy_type               = "StepScaling"
  metric_aggregation_type   = "Average"
  estimated_instance_warmup = 200

  step_adjustment {
    metric_interval_upper_bound = 0
    scaling_adjustment          = -1
  }

  count = "${local.checked_ec2_scaling_policy != "min_max_cpu_only" ? 1:0}"
}

resource "aws_cloudwatch_metric_alarm" "ecs_cluster_memory_scale_in_alarm" {
  alarm_name          = "tf-${var.env}-${var.project}-ecs-${var.cluster_name}-memory-scale-in-alarm"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "5"
  metric_name         = "MemoryReservation"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "${var.scaling_memory_min_percent}"

  dimensions {
    ClusterName = "${local.cluster_name}"
  }

  alarm_description = "This metric monitor ecs cluster memory utilization"
  alarm_actions     = ["${aws_autoscaling_policy.ecs_cluster_memory_scale_in_policy.arn}"]

  count = "${local.checked_ec2_scaling_policy != "min_max_cpu_only" ? 1:0}"
}

resource "aws_autoscaling_schedule" "night" {
  scheduled_action_name  = "night"
  min_size               = 0
  max_size               = 0
  desired_capacity       = 0
  recurrence             = "${var.shutdown_cron_expression}"
  autoscaling_group_name = "${aws_autoscaling_group.ecs.name}"

  count = "${var.env != "prod" && var.auto_shutdown ? 1:0}"
}

resource "aws_autoscaling_schedule" "workday" {
  scheduled_action_name  = "workday"
  min_size               = "${var.autoscaling_min_size}"
  max_size               = "${var.autoscaling_max_size}"
  desired_capacity       = 1
  recurrence             = "${var.startup_cron_expression}"
  autoscaling_group_name = "${aws_autoscaling_group.ecs.name}"

  count = "${var.env != "prod" && var.auto_shutdown ? 1:0}"
}
