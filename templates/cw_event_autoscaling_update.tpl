{
  "source": [
    "aws.autoscaling"
  ],
  "detail-type": [
    "AWS API Call via CloudTrail"
  ],
  "detail": {
    "eventSource": [
      "autoscaling.amazonaws.com"
    ],
    "eventName": [
      "UpdateAutoScalingGroup"
    ],
    "requestParameters": {
      "autoScalingGroupName": [
        "${asg_name}"
      ]
    }
  }
}