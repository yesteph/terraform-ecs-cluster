variable "cluster_name" {
  description = "The name of the ECS cluster."
}

variable "env" {
  description = "The environment of this infrastructure: dev or prod."
}

variable "project" {
  description = "The project related to this cluster."
}

variable "ssh_key_pair" {
  description = "The name of the SSH key pushed to the container instances of the ECS cluster."
}

variable "instance_type" {
  default = "m5.large"
}

variable "http_proxy" {
  description = "The endpoint of the HTTP proxy to go on Internet."
}

variable "vpc_id" {
  description = "The VPC where the cluster must be created."
}

variable "alarm_notification_topic_arn" {
  description = "The ARN where notifications must be sent."
}

variable "enable_alarm_creation" {
  description = "A boolean to indicate if the alarms must be created."
  default     = "true"
}

variable "subnets" {
  type        = "list"
  description = "The list of subnet ids used to create the ECS cluster."
}

variable "aws_region" {
  description = "The AWS region used."
}

variable "commons_ec2_policy_arn" {
  description = "The ARN of the IAM policy used for commons EC2 actions made by the FTP."
}

variable "autoscaling_max_size" {
  description = "The max number of EC2 instances in the ECS cluster."
}

variable "autoscaling_min_size" {
  description = "The min number of EC2 instances in the ECS cluster."
}

variable "bastion_sg" {
  description = "The security group id of bastion SSH."
}

variable "shutdown_cron_expression" {
  description = "The UTC cron expression to shutdown (min=max=desired = 0) the cluster."
  default     = "0 18 * * *"
}

variable "startup_cron_expression" {
  description = "The UTC cron expression to start (min=autoscaling_min_size, max=autoscaling_max_size) the cluster."
  default     = "0 7 * * 1-5"
}

variable "auto_shutdown" {
  description = "Boolean to indicate if the cluster must be shutdown. Bypass to false if env is prod!"
  default     = true
}

variable "ami_id" {
  default     = "false"
  description = "Default is \"false\", then last ecs-* is used. If different from \"false\", use the provided ami_id."
}

variable "ami_lifecycle_tag" {
  default     = "validated"
  description = "The value of the lifecycle tag to select the most recent ami."
}

variable "ec2_scaling_policy" {
  default     = "min_max_cpu_only"
  description = "Determine the policy used to auto scale the EC2 instances in the cluster. Possible values are: min_max_cpu_and_memory | min_max_cpu_only | min_max_memory_only."
}

variable "__ec2_scaling_policy_format" {
  type        = "map"
  description = "Internal variable to validate ec2_scaling_policy"

  default = {
    "min_max_cpu_and_memory" = "min_max_cpu_and_memory"
    "min_max_cpu_only"       = "min_max_cpu_only"
    "min_max_memory_only"    = "min_max_memory_only"
  }
}

variable "scaling_cpu_min_percent" {
  description = "The minimum CPU reservation threshold to remove an instance."
  default     = "50"
}

variable "scaling_cpu_max_percent" {
  description = "The maximum CPU reservation threshold to add an instance."
  default     = "80"
}

variable "scaling_memory_min_percent" {
  description = "The minimum MEMORY reservation threshold to remove an instance."
  default     = "50"
}

variable "scaling_memory_max_percent" {
  description = "The maximum MEMORY reservation threshold to add an instance."
  default     = "75"
}

variable "ecs_heartbeat_timeout" {
  description = "The timeout in seconds to let an ECS instance in 'draining' state. If some ECS tasks are still running after this timeout, they will stopped"
  default     = "600"
}
