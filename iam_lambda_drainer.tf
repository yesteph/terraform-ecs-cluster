data "aws_iam_policy_document" "lambda_drainer_document" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceAttribute",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeHosts",
    ]

    resources = [
      "*",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "sns:Publish",
      "sns:ListSubscriptionsByTopic",
    ]

    resources = [
      "${aws_sns_topic.ec2_lifecycle_notifications.arn}",
      "${var.alarm_notification_topic_arn}",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "ecs:ListContainerInstances",
      "ecs:SubmitContainerStateChange",
      "ecs:SubmitTaskStateChange",
    ]

    resources = [
      "${local.ecs_cluster_arn}",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "ecs:DescribeContainerInstances",
      "ecs:UpdateContainerInstancesState",
      "ecs:ListTasks",
      "ecs:DescribeTasks",
    ]

    resources = [
      "*",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "autoscaling:CompleteLifecycleAction",
    ]

    resources = [
      "${aws_autoscaling_group.ecs.arn}",
    ]
  }
}

resource "aws_iam_policy" "lambda_drainer_execution_policy" {
  name        = "tf-${var.env}-${var.project}-${var.cluster_name}-lambda-drainer"
  description = "IAM policy for Lambda managing draining of tf-${var.env}-${var.project}-${var.cluster_name} ecs cluster."
  policy      = "${data.aws_iam_policy_document.lambda_drainer_document.json}"
}

resource "aws_iam_role" "lambda_drainer_execution_role" {
  name = "tf-${var.env}-${var.project}-${var.cluster_name}-lambda-drainer"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_drainer_role_policy_attach" {
  role       = "${aws_iam_role.lambda_drainer_execution_role.name}"
  policy_arn = "${aws_iam_policy.lambda_drainer_execution_policy.arn}"
}
