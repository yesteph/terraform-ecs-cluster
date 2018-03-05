data "aws_iam_policy_document" "lambda_updater_document" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "ec2:DescribeInstances",
      "autoscaling:DescribeLaunchConfigurations",
    ]

    resources = [
      "*",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "autoscaling:SetDesiredCapacity",
    ]

    resources = [
      "${aws_autoscaling_group.ecs.arn}",
    ]
  }
}

resource "aws_iam_policy" "lambda_updater_execution_policy" {
  name        = "tf-${var.env}-${var.project}-${var.cluster_name}-lambda-updater"
  description = "IAM policy for Lambda managing update of tf-${var.env}-${var.project}-${var.cluster_name} ecs cluster."
  policy      = "${data.aws_iam_policy_document.lambda_updater_document.json}"
}

resource "aws_iam_role" "lambda_updater_execution_role" {
  name = "tf-${var.env}-${var.project}-${var.cluster_name}-lambda-updater"

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

resource "aws_iam_role_policy_attachment" "lambda_updater_role_policy_attach" {
  role       = "${aws_iam_role.lambda_updater_execution_role.name}"
  policy_arn = "${aws_iam_policy.lambda_updater_execution_policy.arn}"
}
