from __future__ import print_function
import boto3
import json
import datetime
import logging
import os


logging.basicConfig()
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Establish boto3 session
session = boto3.session.Session()
logger.debug("Session is in region %s ", session.region_name)

ec2Client = session.client(service_name='ec2')
ecsClient = session.client(service_name='ecs')
asgClient = session.client('autoscaling')
snsClient = session.client('sns')
lambdaClient = session.client('lambda')
alertTopicArn = os.getenv('ALERT_TOPIC_ARN')


"""Publish SNS message to trigger lambda again.
    :param message: To repost the complete original message received when ASG terminating event was received.
    :param topicArn: SNS topic to publish the message to.
"""
def publishToSNS(message, topicArn, subject):
    logger.info("Publish to SNS topic %s, subject %s",topicArn, subject)
    snsResponse = snsClient.publish(
        TopicArn=topicArn,
        Message=json.dumps(message, indent=4),
        Subject=subject
    )
    return "published"


"""Check task status on the ECS container instance ID.
    :param Ec2InstanceId: The EC2 instance ID is used to identify the cluster, container instances in cluster
"""
def checkContainerInstanceTaskStatus(Ec2InstanceId, ClusterName):
    containerInstanceId = None
    clusterName = ClusterName
    tmpMsgAppend = None

    logger.info("Cluster name %s",clusterName)

    # Get list of container instance IDs from the clusterName
    paginator = ecsClient.get_paginator('list_container_instances')
    clusterListPages = paginator.paginate(cluster=clusterName)
    for containerListResp in clusterListPages:
        containerDetResp = ecsClient.describe_container_instances(cluster=clusterName, containerInstances=containerListResp[
            'containerInstanceArns'])
        logger.debug("describe container instances response %s",containerDetResp)

        for containerInstances in containerDetResp['containerInstances']:
            logger.debug("Container Instance ARN: %s and ec2 Instance ID %s",containerInstances['containerInstanceArn'],
                         containerInstances['ec2InstanceId'])
            if containerInstances['ec2InstanceId'] == Ec2InstanceId:
                logger.info("Container instance ID of interest : %s",containerInstances['containerInstanceArn'])
                containerInstanceId = containerInstances['containerInstanceArn']

                # Check if the instance state is set to DRAINING. If not, set it, so the ECS Cluster will handle de-registering instance, draining tasks and draining them
                containerStatus = containerInstances['status']
                if containerStatus == 'DRAINING':
                    logger.info("Container ID %s with EC2 instance-id %s is draining tasks",containerInstanceId,
                                Ec2InstanceId)
                    tmpMsgAppend = {"containerInstanceId": containerInstanceId}
                else:
                    # Make ECS API call to set the container status to DRAINING
                    logger.info("Make ECS API call to set the container status to DRAINING...")
                    ecsResponse = ecsClient.update_container_instances_state(cluster=clusterName,containerInstances=[containerInstanceId],status='DRAINING')
                    # When you set instance state to draining, append the containerInstanceID to the message as well
                    tmpMsgAppend = {"containerInstanceId": containerInstanceId}
                break
            if containerInstanceId is not None:
                break

    # Using container Instance ID, get the task list, and task running on that instance.
    if containerInstanceId != None:
        # List tasks on the container instance ID, to get task Arns
        listTaskResp = ecsClient.list_tasks(cluster=clusterName, containerInstance=containerInstanceId)
        logger.debug("Container instance task list %s",listTaskResp['taskArns'])

        # If the chosen instance has tasks
        if len(listTaskResp['taskArns']) > 0:
            logger.info("%d Tasks are on this instance...%s",len(listTaskResp['taskArns']), Ec2InstanceId)
            return 1, tmpMsgAppend
        else:
            logger.info("NO tasks are on this instance...%s",Ec2InstanceId)
            return 0, tmpMsgAppend
    else:
        logger.info("NO tasks are on this instance....%s",Ec2InstanceId)
        return 0, tmpMsgAppend


def lambda_handler(event, context):

    line = event['Records'][0]['Sns']['Message']
    message = json.loads(line)
    Ec2InstanceId = message['EC2InstanceId']
    asgGroupName = message['AutoScalingGroupName']
    snsArn = event['Records'][0]['EventSubscriptionArn']
    topicArn = event['Records'][0]['Sns']['TopicArn']

    lifecyclehookname = None
    clusterName = None
    tmpMsgAppend = None
    completeHook = 0

    logger.info("Lambda received the event %s",json.dumps(event))
    logger.debug("records: %s",json.dumps(event['Records'][0]))
    logger.debug("sns: %s",json.dumps(event['Records'][0]['Sns']))
    logger.debug("Message: %s",message)
    logger.debug("Ec2 Instance Id %s ,%s",Ec2InstanceId, asgGroupName)
    logger.debug("SNS ARN %s",snsArn)

    # Retrieve the clustername from the Metadata of the hook
    clusterName = json.loads(message['NotificationMetadata'])['ecs_cluster_name']
    logger.debug("ClusterName : %s",clusterName)

    # If the event received is instance terminating...
    if 'LifecycleTransition' in message.keys():
        logger.debug("message autoscaling %s",message['LifecycleTransition'])
        if message['LifecycleTransition'].find('autoscaling:EC2_INSTANCE_TERMINATING') > -1:

            # Get lifecycle hook name
            lifecycleHookName = message['LifecycleHookName']
            logger.info("Setting lifecycle hook name %s ",lifecycleHookName)

            # Check if there are any tasks running on the instance
            tasksRunning, tmpMsgAppend = checkContainerInstanceTaskStatus(Ec2InstanceId, clusterName)
            logger.debug("Returned values received: %s ",tasksRunning)
            if tmpMsgAppend != None:
                message.update(tmpMsgAppend)

            # If tasks are still running...
            if tasksRunning == 1:
                response = snsClient.list_subscriptions_by_topic(TopicArn=topicArn)
                for key in response['Subscriptions']:
                    logger.info("Endpoint %s AND TopicArn %s and protocol %s ",key['Endpoint'], key['TopicArn'],
                                key['Protocol'])
                    if topicArn == key['TopicArn'] and key['Protocol'] == 'lambda':
                        logger.info("TopicArn match, publishToSNS function...")
                        msgResponse = publishToSNS(message, key['TopicArn'], 'Publishing SNS message to invoke lambda again..')
                        logger.debug("msgResponse %s and time is %s",msgResponse, datetime.datetime)
            # If tasks are NOT running...
            elif tasksRunning == 0:
                completeHook = 1
                logger.debug("Setting lifecycle to complete;No tasks are running on instance, completing lifecycle action....")

                try:
                    response = asgClient.complete_lifecycle_action(
                        LifecycleHookName=lifecycleHookName,
                        AutoScalingGroupName=asgGroupName,
                        LifecycleActionResult='CONTINUE',
                        InstanceId=Ec2InstanceId)
                    logger.info("Response received from complete_lifecycle_action %s",response)
                    logger.info("Completedlifecycle hook action")
                except Exception as e:
                    logger.info("Got exception completing lifecycle_action on %s : %s",Ec2InstanceId, str(e))
                    message.update({"exception": str(e)})
                    response = ecsClient.list_container_instances(cluster=clusterName, status='ACTIVE')
                    logger.info('Active container instances: %s',response['containerInstanceArns'])
                    if len(response['containerInstanceArns']) == 0:
                        message = 'No active container instance for cluster {}. Suppose ASG is destroyed - will silently fail.'.format(clusterName)
                        logger.info(message)
                        return
                    message.update({"possibleCause": "Time out to complete lifecycle hook. ECS tasks may have been stopped. You must check"})
                    msgResponse = publishToSNS(message, alertTopicArn, 'Lambda drainer failed to complete lifecycle hook action')