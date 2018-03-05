data "archive_file" "lambda_drainer_archive" {
  type        = "zip"
  source_file = "${path.module}/files/drainer.py"
  output_path = "${path.module}/files/drainer.zip"
}

resource "aws_sns_topic" "ec2_lifecycle_notifications" {
  name = "${aws_autoscaling_group.ecs.name}-lifecycle-notifications"

  display_name = "Topic for EC2 lifecycle hooks on auto scaling group ${aws_autoscaling_group.ecs.name}"
}

resource "aws_lambda_function" "drainer" {
  filename         = "${path.module}/files/drainer.zip"
  function_name    = "tf-${var.env}-${var.project}-${var.cluster_name}-drainer"
  role             = "${aws_iam_role.lambda_drainer_execution_role.arn}"
  handler          = "drainer.lambda_handler"
  source_code_hash = "${data.archive_file.lambda_drainer_archive.output_base64sha256}"
  runtime          = "python3.6"
  description      = "Drain ECS container instances"

  memory_size = 128
  timeout     = 3

  environment {
    variables = {
      ALERT_TOPIC_ARN = "${var.alarm_notification_topic_arn}"
    }
  }

  depends_on = ["data.archive_file.lambda_drainer_archive", "aws_iam_role_policy_attachment.lambda_drainer_role_policy_attach"]
}

resource "aws_lambda_permission" "from_sns_to_drainer" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.drainer.function_name}"
  principal     = "sns.amazonaws.com"
  source_arn    = "${aws_sns_topic.ec2_lifecycle_notifications.arn}"
}

resource "aws_sns_topic_subscription" "lambda_drainer" {
  topic_arn = "${aws_sns_topic.ec2_lifecycle_notifications.arn}"
  protocol  = "lambda"
  endpoint  = "${aws_lambda_function.drainer.arn}"
}
