data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "ecs_instance_policy" {
  name        = "tf-${var.env}-${var.project}-${var.cluster_name}-ecs-instance"
  description = "IAM policy for ECS instance containers"                        # TODO add filter on ec2:CreateTags

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:DeregisterContainerInstance",
        "ecs:DiscoverPollEndpoint",
        "ecs:Poll",
        "ecs:RegisterContainerInstance",
        "ecs:StartTelemetrySession",
        "ecs:UpdateContainerInstancesState",
        "ecs:Submit*",
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "ecs_instance_role" {
  name = "tf-${var.env}-${var.project}-${var.cluster_name}-ecs"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs_instance_role_policy_attach" {
  role       = "${aws_iam_role.ecs_instance_role.name}"
  policy_arn = "${aws_iam_policy.ecs_instance_policy.arn}"
}

resource "aws_iam_role_policy_attachment" "ec2_commons_instance_role_policy_attach" {
  role       = "${aws_iam_role.ecs_instance_role.name}"
  policy_arn = "${var.commons_ec2_policy_arn}"
}

resource "aws_iam_instance_profile" "ecs_container_instance_profile" {
  name = "tf-${var.env}-${var.project}-${var.cluster_name}-ecs"
  role = "${aws_iam_role.ecs_instance_role.name}"

  depends_on = ["aws_iam_role_policy_attachment.ecs_instance_role_policy_attach",
    "aws_iam_role.ecs_instance_role",
  ]
}

/*
ecsServiceRole : needed to allow Load Balancing on ECS services
*/

resource "aws_iam_policy" "ecs_container_service_policy" {
  name        = "tf-${var.env}-${var.project}-ecs-container-service"
  description = "IAM policy for ECS Container services."

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:Describe*",
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:Describe*",
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:RegisterTargets"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "ecs_container_service_role" {
  name = "tf-${var.env}-${var.project}-ecs-container-service"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs_container_service_role_policy_attach" {
  role       = "${aws_iam_role.ecs_container_service_role.name}"
  policy_arn = "${aws_iam_policy.ecs_container_service_policy.arn}"
}

// ecsAutoscaleRole

resource "aws_iam_policy" "ecs_auto_scale_policy" {
  name        = "tf-${var.env}-${var.project}-ecs-autoscale"
  description = "IAM policy for ECS auto scaling."

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
          "ecs:DescribeServices",
          "ecs:UpdateService",
          "cloudwatch:DescribeAlarms"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "ecs_auto_scale_role" {
  name = "tf-${var.env}-${var.project}-ecs-autoscale"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "application-autoscaling.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs_auto_scale_role_policy_attach" {
  role       = "${aws_iam_role.ecs_auto_scale_role.name}"
  policy_arn = "${aws_iam_policy.ecs_auto_scale_policy.arn}"
}

resource "aws_iam_role" "ecs_notification_role" {
  name = "tf-${var.env}-${var.project}-${var.cluster_name}-ecs-notification"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "autoscaling.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs_notification_role_policy_attach" {
  role       = "${aws_iam_role.ecs_notification_role.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AutoScalingNotificationAccessRole"
}
