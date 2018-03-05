from __future__ import print_function
import boto3
import json
from datetime import datetime
import logging
import os

class ConnectivityTimeoutException(Exception): pass

logging.basicConfig()
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Establish boto3 session
session = boto3.session.Session()
logger.debug("Session is in region %s ", session.region_name)

ec2Client = session.client(service_name='ec2')
asgClient = session.client('autoscaling')
ecsClient = session.client(service_name='ecs')

def lambda_handler(event, context):
    logger.info("Lambda received the event %s",json.dumps(event, indent=4))
    ec2InstanceId = event['detail']['EC2InstanceId']
    autoscalingGroupName = event['detail']['AutoScalingGroupName']
    startTime = datetime.strptime(event['time'], "%Y-%m-%dT%H:%M:%SZ")
    logger.info("EC2Instance ID : %s", ec2InstanceId)
    logger.info("Auto scaling group name : %s", autoscalingGroupName)
    logger.info("StartTime: %s", startTime)

    asg = asgClient.describe_auto_scaling_groups(
        AutoScalingGroupNames=[
            autoscalingGroupName,
        ])['AutoScalingGroups'][0]

    logger.debug(asg)

    ecsClusterName = list(filter(lambda x:x['Key'] == 'ecs_cluster', asg['Tags']))[0]['Value']
    logger.info("ECS cluster name : {}".format(ecsClusterName))

    # Get list of container instance IDs from the clusterName
    paginator = ecsClient.get_paginator('list_container_instances')
    clusterListPages = paginator.paginate(cluster=ecsClusterName)
    for containerListResp in clusterListPages:
        logger.info('Page: %s', containerListResp)
        containerDetResp = ecsClient.describe_container_instances(cluster=ecsClusterName, containerInstances=containerListResp[
            'containerInstanceArns'])
        logger.debug("describe container instances response %s",containerDetResp)

        for containerInstances in containerDetResp['containerInstances']:
            logger.info("Container Instance ARN: %s and ec2 Instance ID %s",containerInstances['containerInstanceArn'],
                         containerInstances['ec2InstanceId'])
            if containerInstances['ec2InstanceId'] == ec2InstanceId:
                message = "Container instance ID {} matches current EC2 {}".format(containerInstances['containerInstanceArn'], ec2InstanceId)
                logger.info(message)
                return {"isConnected": True, "message": message}

    # check source event time not more than 24 Hours
    elapsedTime = datetime.utcnow() - startTime
    if elapsedTime.seconds >= 300:
        logger.info("ECS agent has not been connected within 5 minutes!!")
        response = asgClient.set_instance_health(
            InstanceId=ec2InstanceId,
            HealthStatus='Unhealthy',
            ShouldRespectGracePeriod=False
        )
        logger.info(response)
        raise ConnectivityTimeoutException("ECS agent has not been connected within 5 minutes!!")

    message = "ECS agent is not connected. Wait a while"
    logger.info(message)
    return {"isConnected": False, "message": message}