## Description

This module creates an EC2 autoscaling group for an ECS cluster.

The provisioned elements are :
* cloudwatch loggroups
* cloudwatch alarms
* EC2 auto scaling group and scaling policies
* IAM policies and roles
* security groups
* Lambda function and SNS topic to drain EC2 instances before terminating
* Lambda function and Step function state machine to update EC2 instances when ami-id or instance-type has been changed
* Lambda function and Step function state machine to ensure any new launched EC2 instance is visible as a container instance by the ECS service.

If the **env** variable is prod, then the ECS cluster resource is marked as prevent_destroy : all destroy plan will crash.

### Cloudwatch log groups

In addition of the common log groups created by the terraform-ec2-common-cwlog-module, the following log groups are created with a retention of 14 days :
* **/ec2/${var.env}/${local.component_id}/ecs/ecs-agent.log**
* **/ec2/${var.env}/${local.component_id}/docker**
* **/ec2/${var.env}/${local.component_id}/ecs/audit.log**
* **/ec2/${var.env}/${local.component_id}/ecs/ecs-init.log**

Where **local.component_id** is **"tf-${var.env}-${var.project}-ecs-${var.cluster_name}"**.

### Cloudwatch alarms

An Out Of Memory alarm is created, based on counting "died due to OOM" pattern in the ECS agent logs.
A "max-size-alarm" is created, based on 90% of the max size of the auto scaling group.

### EC2 resources

#### launch configuration

AMI selection for the launch configuration is branched according to the presence of the var.ami_id.
If var.ami_id is specified, it is used.
If not, we use the latest AMI whose name is ecs-*, architecture is x86_64, the tag:lifecycle matching the var.ami_lifecycle_tag and owner is 028907936641 (Transverse account).

It provides a user-data script which configure awslogs agent, ecs agent and docker daemon to use the specified HTTP proxy.
Note if instance_type is not t2.*, ebs_optimized is set.

#### auto scaling group

The auto-scaling group enables advanced metrics.
Propagated tags are :
* cost:environment
* cost:cost-center
* cost:project

#### scale-in / scale-out policies

4 policies are defined :
* CPU based scale-out
* Memory based scale-out
* CPU base scale-in
* Memory based scale-in

CPU and Memory are based on "Reservation" of the cluster. That means you **must** define CPU and Memory reservation when you define ECS tasks/services.

Use the parameter **ec2_scaling_policy** to define the policies you want to declare. Possible values of **ec2_scaling_policy** are **min_max_cpu_and_memory** | **min_max_cpu_only** | **min_max_memory_only**.
Using **cpu_and_memory** supposes you **will** declare ECS tasks AND EC2 instance type with a similar CPU/memory ratio. 

#### scheduled actions

If ${var.env} is not "prod", scheduled actions are set to scale-in 0 instances during nights and weekends.

You can use auto_shutdown to disable auto shutdown for non prod cluster.
In addition, times for this auto shutdown/startup can be configured with startup_cron_expression and shutdown_cron_expression.  

### IAM policies and roles

A role for the EC2 instances of the cluster is provisioned.
It is attached to :
* an IAM policy for standard ECS container instances (ECR / ecs API)
* the provided commons_ec2_policy

In addition, 2 roles are created :
* A container service role, to manage load-balancing and service launch/registration
* An autoscale role, to update ECS services

### Security groups

A security group is created for the cluster.
It allows SSH from the provided bastion security group.

The security group is outputted to allow further rules to be added.

### "Drainer" Lambda function and SNS topic

Using lifecycle hooks, all EC2_INSTANCE_TERMINATING events from the auto scaling group are sent to an SNS topic which triggers a lambda.
This "drainer" lambda calls 'drain' on the EC2 instance planned for termination. When there is no more running ECS tasks on the instance, the lifecycle is completed.
Then termination carry on.

Timeout on the lifecycle is 300 seconds.

### "Updater" Lambda function and state-machine

Using CloudWatch Event rules, all API calls to UpdateLaunchConfiguration for the ECS autoscaling group are sent to a step function "updater".
This step function calls an "updater" lambda which checks if the ECS autoscaling group must be updated (check: AMI, instance type).
If must, then set desired_count value.
The step function asserts the lambda return code to determine if the update is done. If not, it waits for 10 minutes then call again the "updater" lambda.

After 24H if some EC2 instances are not updated, the step function fails.
A cloudwatch alarm is set to send notifications if the step function fails.

### "Launch" Lambda function and state-machine

Using CloudWatch Event rules, all API calls to LaunchInstance for the ECS autoscaling group are sent to a step function "launch".
This step function calls an "launch" lambda which checks if the launched EC2 instance is visible as a container instance id.
The step function asserts the lambda return code to determine if the ECS agent on the VM is connected. If not, it waits for 30 seconds then call again the "launch" lambda.

After 300 seconds if the EC2 instance is still nor connected, the step function fails.
A cloudwatch alarm is set to send notifications if the step function fails.


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|:----:|:-----:|:-----:|
| __ec2_scaling_policy_format | Internal variable to validate ec2_scaling_policy | map | `<map>` | no |
| alarm_notification_topic_arn | The ARN where notifications must be sent. | string | - | yes |
| ami_id | Default is "false", then last ecs-* is used. If different from "false", use the provided ami_id. | string | `false` | no |
| ami_lifecycle_tag | The value of the lifecycle tag to select the most recent ami. | string | `validated` | no |
| auto_shutdown | Boolean to indicate if the cluster must be shutdown. Bypass to false if env is prod! | string | `true` | no |
| autoscaling_max_size | The max number of EC2 instances in the ECS cluster. | string | - | yes |
| autoscaling_min_size | The min number of EC2 instances in the ECS cluster. | string | - | yes |
| aws_region | The AWS region used. | string | - | yes |
| bastion_sg | The security group id of bastion SSH. | string | - | yes |
| cluster_name | The name of the ECS cluster. | string | - | yes |
| commons_ec2_policy_arn | The ARN of the IAM policy used for commons EC2 actions made by the FTP. | string | - | yes |
| ec2_scaling_policy | Determine the policy used to auto scale the EC2 instances in the cluster. Possible values are: min_max_cpu_and_memory | min_max_cpu_only | min_max_memory_only. | string | `min_max_cpu_only` | no |
| ecs_heartbeat_timeout | The timeout in seconds to let an ECS instance in 'draining' state. If some ECS tasks are still running after this timeout, they will stopped | string | `600` | no |
| enable_alarm_creation | A boolean to indicate if the alarms must be created. | string | `true` | no |
| env | The environment of this infrastructure: dev or prod. | string | - | yes |
| http_proxy | The endpoint of the HTTP proxy to go on Internet. | string | - | yes |
| instance_type |  | string | `m5.large` | no |
| project | The project related to this cluster. | string | - | yes |
| scaling_cpu_max_percent | The maximum CPU reservation threshold to add an instance. | string | `80` | no |
| scaling_cpu_min_percent | The minimum CPU reservation threshold to remove an instance. | string | `50` | no |
| scaling_memory_max_percent | The maximum MEMORY reservation threshold to add an instance. | string | `75` | no |
| scaling_memory_min_percent | The minimum MEMORY reservation threshold to remove an instance. | string | `50` | no |
| shutdown_cron_expression | The UTC cron expression to shutdown (min=max=desired = 0) the cluster. | string | `0 18 * * *` | no |
| ssh_key_pair | The name of the SSH key pushed to the container instances of the ECS cluster. | string | - | yes |
| startup_cron_expression | The UTC cron expression to start (min=autoscaling_min_size, max=autoscaling_max_size) the cluster. | string | `0 7 * * 1-5` | no |
| subnets | The list of subnet ids used to create the ECS cluster. | list | - | yes |
| vpc_id | The VPC where the cluster must be created. | string | - | yes |

## Outputs

| Name | Description |
|------|-------------|
| ami_id | The name of the used AMI |
| autoscaling_group_name | The name of the created autoscaling group |
| ecs_cluster_arn |  |
| ecs_cluster_name |  |
| ecs_cluster_security_group_id |  |
| iam_ecs_autoscale_role_arn |  |
| iam_ecs_service_role_arn |  |
