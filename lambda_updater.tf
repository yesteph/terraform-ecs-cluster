data "archive_file" "lambda_updater_archive" {
  type        = "zip"
  source_file = "${path.module}/files/updater.py"
  output_path = "${path.module}/files/updater.zip"
}

resource "aws_lambda_function" "updater" {
  filename         = "${path.module}/files/updater.zip"
  function_name    = "tf-${var.env}-${var.project}-${var.cluster_name}-updater"
  role             = "${aws_iam_role.lambda_updater_execution_role.arn}"
  handler          = "updater.lambda_handler"
  source_code_hash = "${data.archive_file.lambda_updater_archive.output_base64sha256}"
  runtime          = "python3.6"
  description      = "Update ECS container instances"

  memory_size = 128
  timeout     = 3

  depends_on = ["data.archive_file.lambda_updater_archive", "aws_iam_role_policy_attachment.lambda_updater_role_policy_attach"]
}
