resource "aws_iam_role" "sfn_asg_updater_execution_role" {
  name = "${aws_autoscaling_group.ecs.name}-state-machine-updater"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "states.eu-west-1.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

data "aws_iam_policy_document" "sfn_asg_updater" {
  statement {
    effect = "Allow"

    actions = [
      "lambda:InvokeFunction",
    ]

    resources = [
      "${aws_lambda_function.updater.arn}",
    ]
  }
}

resource "aws_iam_policy" "sfn_asg_updater" {
  name        = "${aws_autoscaling_group.ecs.name}-state-machine-updater"
  description = "IAM policy for the state machine used to update auto scaling group ${aws_autoscaling_group.ecs.name}."
  policy      = "${data.aws_iam_policy_document.sfn_asg_updater.json}"
}

resource "aws_iam_role_policy_attachment" "sfn_asg_updater_role_policy_attach" {
  role       = "${aws_iam_role.sfn_asg_updater_execution_role.name}"
  policy_arn = "${aws_iam_policy.sfn_asg_updater.arn}"
}

resource "aws_sfn_state_machine" "asg_updater" {
  name     = "${aws_autoscaling_group.ecs.name}-state-machine-updater"
  role_arn = "${aws_iam_role.sfn_asg_updater_execution_role.arn}"

  definition = <<EOF
{
  "Comment": "A state machine to smoothly recreate EC2 instances for autoscaling group ${aws_autoscaling_group.ecs.name}. Invoked at each update of the ASG.",
   "StartAt": "UpdateASGCapacity",
  "States": {
    "UpdateASGCapacity": {
      "Type": "Task",
      "Resource": "${aws_lambda_function.updater.arn}",
      "TimeoutSeconds": ${aws_lambda_function.updater.timeout},
      "OutputPath": "$",
      "ResultPath": "$.updateASGCapacityOutput",
      "Next": "IsUpdateFinished"
    },
    "IsUpdateFinished": {
      "Type" : "Choice",
      "Choices": [
        {
          "Variable": "$.updateASGCapacityOutput.updateIsFinished",
          "BooleanEquals": true,
          "Next": "UpdateFinished"
        },
        {
          "Variable": "$.updateASGCapacityOutput.updateIsFinished",
          "BooleanEquals": false,
          "Next": "WaitCapacityChange"
        }
      ],
      "Default": "UpdateFinished"
    },

    "WaitCapacityChange": {
      "Type": "Wait",
      "Seconds": 600,
      "Next": "UpdateASGCapacity"
    },

    "UpdateFinished": {
      "Type": "Pass",
      "End": true
    }
  }
}
EOF
}
