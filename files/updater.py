from __future__ import print_function
import boto3
import json
from datetime import datetime
import logging
import os

class UpdateTimedoutException(Exception): pass
class UpdateNotFinishedException(Exception): pass

logging.basicConfig()
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Establish boto3 session
session = boto3.session.Session()
logger.debug("Session is in region %s ", session.region_name)

ec2Client = session.client(service_name='ec2')
asgClient = session.client('autoscaling')
snsClient = session.client('sns')
lambdaClient = session.client('lambda')

def lambda_handler(event, context):
    logger.info("Lambda received the event %s",json.dumps(event, indent=4))
    launchConfigurationName = event['detail']['requestParameters'].get('launchConfigurationName', None)
    if launchConfigurationName is None:
        message = 'Current event has no launch configuration name. Consider update of EC2 VM is not necessary.'
        logger.info(message)
        return {"updateIsFinished": True, "message": message}

    autoscalingGroupName = event['detail']['requestParameters']['autoScalingGroupName']
    eventTime = datetime.strptime(event['detail']['eventTime'], "%Y-%m-%dT%H:%M:%SZ")
    logger.info("Launch configuration : %s", launchConfigurationName)
    logger.info("Auto scaling group name : %s", autoscalingGroupName)
    logger.info("Event time: %s", eventTime)

    asg = asgClient.describe_auto_scaling_groups(
        AutoScalingGroupNames=[
            autoscalingGroupName,
        ])['AutoScalingGroups'][0]

    logger.debug(asg)

    # Check if the received launch_config is the last attached to the ASG. If not => ASG has changes after
    if asg['LaunchConfigurationName'] != launchConfigurationName:
        message = 'Current launch configuration ({}) != received ({}). Another state-machine execution will proceed it'.format(asg['LaunchConfigurationName'], launchConfigurationName)
        logger.info(message)
        return {"updateIsFinished": True, "message": message}

    targetLaunchConfiguration = asgClient.describe_launch_configurations(
        LaunchConfigurationNames=[
            launchConfigurationName,
        ])['LaunchConfigurations'][0]

    logger.info("Target ImageId : %s",targetLaunchConfiguration['ImageId'])
    logger.info("Target InstanceType : %s",targetLaunchConfiguration['InstanceType'])

    instanceIds = list(map(lambda x:x['InstanceId'], asg['Instances']))

    logger.info("Inspect current instances in ASG: %s",instanceIds)

    paginator = ec2Client.get_paginator('describe_instances')
    instancePages = paginator.paginate(Filters=[
        {
            'Name': 'image-id',
            'Values': [
                targetLaunchConfiguration['ImageId'],
            ]
        },
        {
            'Name': 'instance-type',
            'Values': [
                targetLaunchConfiguration['InstanceType'],
            ]
        }
    ],
        InstanceIds=instanceIds)

    okInstances = []
    for instanceSet in instancePages:
        for reservation in instanceSet['Reservations']:
            okInstances.extend(reservation['Instances'])

    logger.info("OK instances : %s", okInstances)
    logger.info("%d instances in ASG, %d are ok",len(asg['Instances']), len(okInstances))

    # check source event time not more than 24 Hours
    elapsedTime = datetime.utcnow() - eventTime
    if elapsedTime.days >= 1:
        logger.info("Update has taken more than 1 day!!")
        raise UpdateTimedoutException("Update took more than 1 day")

    if len(asg['Instances']) != len(okInstances):
        nbInstanceToUpdate = len(asg['Instances']) - len(okInstances)
        newDesired = min(asg['MaxSize'], asg['DesiredCapacity'] + nbInstanceToUpdate)
        logger.info("Must update %d instances but will set desired_capacity to %d", nbInstanceToUpdate,newDesired)

        try:
            response = asgClient.set_desired_capacity(
                AutoScalingGroupName=autoscalingGroupName,
                DesiredCapacity=newDesired,
                HonorCooldown=False
            )
            logger.info(response)
        except ScalingActivityInProgressFault as e:
            logger.info("Error setting desired_capacity : %s",str(e))
        finally:
            return {"updateIsFinished": False, "message": "Wait desired_count is taken into account"}

    return {"updateIsFinished": True, "message": "All instances seem updated."}