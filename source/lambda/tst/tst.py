"""Test Module"""
import logging
import json
import boto3    # pylint: disable=unused-import

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)
logging.getLogger('boto3').setLevel(logging.ERROR)
logging.getLogger('botocore').setLevel(logging.ERROR)

def handler(event, context):
    # pylint: disable=unused-argument
    """Lambda Entry"""
    LOGGER.info('event: %s', json.dumps(event))
