data "aws_iam_policy_document" "lambda_launch_document" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "autoscaling:DescribeAutoScalingGroups",
      "ecs:DescribeContainerInstances",
    ]

    resources = [
      "*",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "ecs:ListContainerInstances",
    ]

    resources = [
      "${local.ecs_cluster_arn}",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "autoscaling:SetInstanceHealth",
    ]

    resources = [
      "${aws_autoscaling_group.ecs.arn}",
    ]
  }
}

resource "aws_iam_policy" "lambda_launch_execution_policy" {
  name        = "tf-${var.env}-${var.project}-${var.cluster_name}-lambda-launch"
  description = "IAM policy for Lambda to ensure a newly launched EC2 instance is OK in tf-${var.env}-${var.project}-${var.cluster_name} ecs cluster."
  policy      = "${data.aws_iam_policy_document.lambda_launch_document.json}"
}

resource "aws_iam_role" "lambda_launch_execution_role" {
  name = "tf-${var.env}-${var.project}-${var.cluster_name}-lambda-launch"

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

resource "aws_iam_role_policy_attachment" "lambda_launch_role_policy_attach" {
  role       = "${aws_iam_role.lambda_launch_execution_role.name}"
  policy_arn = "${aws_iam_policy.lambda_launch_execution_policy.arn}"
}
