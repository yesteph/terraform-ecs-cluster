locals {
  checked_ec2_scaling_policy = "${lookup(var.__ec2_scaling_policy_format, var.ec2_scaling_policy)}"

  cluster_name              = "tf-${var.env}-${var.project}-${var.cluster_name}"
  component_id              = "tf-${var.env}-${var.project}-ecs-${var.cluster_name}"
  ecs_cluster_arn           = "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${local.cluster_name}"
  state_machine_updater_arn = "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${aws_sfn_state_machine.asg_updater.name}"
  state_machine_launch_arn  = "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${aws_sfn_state_machine.asg_launch.name}"
}
