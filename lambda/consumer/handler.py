import json


def handler(event, context):
    for record in event["Records"]:
        body = json.loads(record["body"])
        task = body.get("task", "unknown task")
        print(f"Processing task: {task}")

    return {"statusCode": 200}
