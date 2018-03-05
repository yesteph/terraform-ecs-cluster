resource "aws_iam_role" "cw_event_rule_asg_launch_execution_role" {
  name = "${aws_autoscaling_group.ecs.name}-cw-event-autoscaling-launch"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

data "aws_iam_policy_document" "cw_event_rule_asg_launch" {
  statement {
    effect = "Allow"

    actions = [
      "states:StartExecution",
    ]

    resources = [
      "${local.state_machine_launch_arn}",
    ]
  }
}

resource "aws_iam_policy" "cw_event_rule_asg_launch" {
  name        = "${local.component_id}-cw-event-autoscaling-launch"
  description = "IAM policy for the cloudwatch event rule used to check ECS agent status in a launched instance in auto scaling group ${aws_autoscaling_group.ecs.name}."
  policy      = "${data.aws_iam_policy_document.cw_event_rule_asg_launch.json}"
}

resource "aws_iam_role_policy_attachment" "cw_event_rule_asg_launch_role_policy_attach" {
  role       = "${aws_iam_role.cw_event_rule_asg_launch_execution_role.name}"
  policy_arn = "${aws_iam_policy.cw_event_rule_asg_launch.arn}"
}

data "template_file" "asg_launch_event_pattern" {
  template = "${file("${path.module}/templates/cw_event_autoscaling_launch.tpl")}"

  vars {
    asg_name = "${aws_autoscaling_group.ecs.name}"
  }
}

resource "aws_cloudwatch_event_rule" "autoscaling_launch" {
  name          = "${local.component_id}-asg-launch"
  description   = "Capture launch in autoscaling group ${aws_autoscaling_group.ecs.name}"
  event_pattern = "${data.template_file.asg_launch_event_pattern.rendered}"
}

resource "aws_cloudwatch_event_target" "sfn_asg_launch" {
  rule     = "${aws_cloudwatch_event_rule.autoscaling_launch.name}"
  role_arn = "${aws_iam_role.cw_event_rule_asg_launch_execution_role.arn}"
  arn      = "${local.state_machine_launch_arn}"
}
