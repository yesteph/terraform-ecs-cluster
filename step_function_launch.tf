resource "aws_iam_role" "sfn_asg_launch_execution_role" {
  name = "${aws_autoscaling_group.ecs.name}-state-machine-launch"

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

data "aws_iam_policy_document" "sfn_asg_launch" {
  statement {
    effect = "Allow"

    actions = [
      "lambda:InvokeFunction",
    ]

    resources = [
      "${aws_lambda_function.launch.arn}",
    ]
  }
}

resource "aws_iam_policy" "sfn_asg_launch" {
  name        = "${aws_autoscaling_group.ecs.name}-state-machine-launch"
  description = "IAM policy for the state machine used to check a new ECS container instance is up for cluster ${local.cluster_name}."
  policy      = "${data.aws_iam_policy_document.sfn_asg_launch.json}"
}

resource "aws_iam_role_policy_attachment" "sfn_asg_launch_role_policy_attach" {
  role       = "${aws_iam_role.sfn_asg_launch_execution_role.name}"
  policy_arn = "${aws_iam_policy.sfn_asg_launch.arn}"
}

resource "aws_sfn_state_machine" "asg_launch" {
  name     = "${aws_autoscaling_group.ecs.name}-state-machine-launch"
  role_arn = "${aws_iam_role.sfn_asg_launch_execution_role.arn}"

  definition = <<EOF
{
  "Comment": "A state machine to check a new ECS container instance is up for cluster ${local.cluster_name}. Invoked at each launch of an EC2 VM.",
   "StartAt": "CheckECSAgentConnectivity",
  "States": {
    "CheckECSAgentConnectivity": {
      "Comment": "Returns status of ECS agent connection. If source event has more than 5 minutes, marks the instance as unhealthy.",
      "Type": "Task",
      "Resource": "${aws_lambda_function.launch.arn}",
      "TimeoutSeconds": ${aws_lambda_function.launch.timeout},
      "OutputPath": "$",
      "ResultPath": "$.checkECSAgentConnectivityOutput",
      "Next": "IsECSAgentConnected"
    },
    "IsECSAgentConnected": {
      "Type" : "Choice",
      "Choices": [
        {
          "Variable": "$.checkECSAgentConnectivityOutput.isConnected",
          "BooleanEquals": true,
          "Next": "AgentConnected"
        },
        {
          "Variable": "$.checkECSAgentConnectivityOutput.isConnected",
          "BooleanEquals": false,
          "Next": "WaitAgentConnects"
        }
      ],
      "Default": "AgentConnected"
    },

    "WaitAgentConnects": {
      "Type": "Wait",
      "Seconds": 30,
      "Next": "CheckECSAgentConnectivity"
    },

    "AgentConnected": {
      "Type": "Pass",
      "End": true
    }
  }
}
EOF
}
