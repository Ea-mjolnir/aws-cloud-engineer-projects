import json
import os
import logging
from aws_xray_sdk.core import xray_recorder, patch_all

patch_all()

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    """
    Processes task events from SQS.
    In production this would send emails via SES, push to SNS, write to a
    notifications table, trigger webhooks, etc.
    """
    for record in event.get("Records", []):
        try:
            body       = json.loads(record["body"])
            event_type = body.get("event")
            user_id    = body.get("userId")
            task_id    = body.get("taskId")

            logger.info(json.dumps({
                "action":    "process_notification",
                "eventType": event_type,
                "userId":    user_id,
                "taskId":    task_id,
                "messageId": record["messageId"]
            }))

            # Route to appropriate handler based on event type
            if event_type == "TASK_CREATED":
                handle_task_created(body)
            elif event_type == "TASK_COMPLETED":
                handle_task_completed(body)
            else:
                logger.warning(json.dumps({"warning": "Unknown event type", "eventType": event_type}))

        except Exception as e:
            # Raising here causes SQS to retry and eventually route to DLQ
            logger.error(json.dumps({"error": str(e), "record": record}))
            raise


@xray_recorder.capture("handle_task_created")
def handle_task_created(body):
    logger.info(json.dumps({
        "notification": "task_created",
        "userId":       body["userId"],
        "taskId":       body["taskId"]
    }))
    # TODO: send email via SES, push notification via SNS, etc.


@xray_recorder.capture("handle_task_completed")
def handle_task_completed(body):
    logger.info(json.dumps({
        "notification": "task_completed",
        "userId":       body["userId"],
        "taskId":       body["taskId"]
    }))
