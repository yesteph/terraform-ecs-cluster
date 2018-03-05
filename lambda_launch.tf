data "archive_file" "lambda_launch_archive" {
  type        = "zip"
  source_file = "${path.module}/files/launch.py"
  output_path = "${path.module}/files/launch.zip"
}

resource "aws_lambda_function" "launch" {
  filename         = "${path.module}/files/launch.zip"
  function_name    = "tf-${var.env}-${var.project}-${var.cluster_name}-launch"
  role             = "${aws_iam_role.lambda_launch_execution_role.arn}"
  handler          = "launch.lambda_handler"
  source_code_hash = "${data.archive_file.lambda_launch_archive.output_base64sha256}"
  runtime          = "python3.6"
  description      = "Ensure an ECS container instance is running."

  memory_size = 128
  timeout     = 3

  depends_on = ["data.archive_file.lambda_launch_archive", "aws_iam_role_policy_attachment.lambda_launch_role_policy_attach"]
}
