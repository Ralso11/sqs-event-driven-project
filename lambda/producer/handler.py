import json
import os
import boto3

sqs = boto3.client("sqs")
QUEUE_URL = os.environ["QUEUE_URL"]


def handler(event, context):
    body = json.loads(event.get("body") or "{}")
    task = body.get("task", "no task specified")

    sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps({"task": task})
    )

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message": "Task queued successfully",
            "task": task
        })
    }
