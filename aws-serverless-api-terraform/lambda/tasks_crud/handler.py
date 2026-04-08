import json
import os
import uuid
import boto3
import logging
from datetime import datetime, timezone
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Instrument all AWS SDK calls with X-Ray
patch_all()

# Structured logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
s3_client = boto3.client("s3")
sqs_client = boto3.client("sqs")

TABLE_NAME   = os.environ["DYNAMODB_TABLE"]
BUCKET_NAME  = os.environ["S3_BUCKET"]
QUEUE_URL    = os.environ["SQS_QUEUE_URL"]
table        = dynamodb.Table(TABLE_NAME)


def log_event(action, user_id, task_id=None, extra=None):
    """Structured log — searchable in CloudWatch Logs Insights."""
    logger.info(json.dumps({
        "action":    action,
        "userId":    user_id,
        "taskId":    task_id,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        **(extra or {})
    }))


def get_user_id(event):
    """Extract authenticated user ID from Cognito JWT claims."""
    claims = event.get("requestContext", {}) \
                  .get("authorizer", {}) \
                  .get("claims", {})
    user_id = claims.get("sub")
    if not user_id:
        raise ValueError("Unauthenticated request — no user sub in claims")
    return user_id


def build_response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type":                "application/json",
            "Access-Control-Allow-Origin": "*",
            "X-Content-Type-Options":      "nosniff"
        },
        "body": json.dumps(body)
    }


@xray_recorder.capture("create_task")
def create_task(event, user_id):
    body = json.loads(event.get("body", "{}"))

    # Input validation
    title = body.get("title", "").strip()
    if not title or len(title) > 200:
        return build_response(400, {"error": "Title is required and must be under 200 characters"})

    task_id   = str(uuid.uuid4())
    now       = datetime.now(timezone.utc).isoformat()
    status    = body.get("status", "PENDING")
    valid_statuses = ["PENDING", "IN_PROGRESS", "DONE"]

    if status not in valid_statuses:
        return build_response(400, {"error": f"Status must be one of {valid_statuses}"})

    item = {
        "PK":          f"USER#{user_id}",
        "SK":          f"TASK#{task_id}",
        "GSI1PK":      f"STATUS#{status}",
        "GSI1SK":      f"CREATED#{now}",
        "taskId":      task_id,
        "userId":      user_id,
        "title":       title,
        "description": body.get("description", ""),
        "status":      status,
        "priority":    body.get("priority", "MEDIUM"),
        "createdAt":   now,
        "updatedAt":   now,
    }

    table.put_item(Item=item)

    # Send async notification event to SQS
    sqs_client.send_message(
        QueueUrl    = QUEUE_URL,
        MessageBody = json.dumps({
            "event":  "TASK_CREATED",
            "userId": user_id,
            "taskId": task_id,
            "title":  title,
        }),
        MessageAttributes={
            "eventType": {
                "StringValue": "TASK_CREATED",
                "DataType":    "String"
            }
        }
    )

    log_event("create_task", user_id, task_id)
    return build_response(201, {"taskId": task_id, "message": "Task created"})


@xray_recorder.capture("list_tasks")
def list_tasks(event, user_id):
    params = event.get("queryStringParameters") or {}
    status_filter = params.get("status")

    if status_filter:
        # Query via GSI for status-based filtering
        result = table.query(
            IndexName                 = "StatusIndex",
            KeyConditionExpression    = "GSI1PK = :pk",
            FilterExpression          = "userId = :uid",
            ExpressionAttributeValues = {
                ":pk":  f"STATUS#{status_filter}",
                ":uid": user_id
            }
        )
    else:
        # Query all tasks for this user
        result = table.query(
            KeyConditionExpression    = "PK = :pk AND begins_with(SK, :sk)",
            ExpressionAttributeValues = {
                ":pk": f"USER#{user_id}",
                ":sk": "TASK#"
            }
        )

    log_event("list_tasks", user_id, extra={"count": len(result["Items"])})
    return build_response(200, {
        "tasks": result["Items"],
        "count": len(result["Items"])
    })


@xray_recorder.capture("get_task")
def get_task(event, user_id):
    task_id = event["pathParameters"]["taskId"]
    result  = table.get_item(Key={
        "PK": f"USER#{user_id}",
        "SK": f"TASK#{task_id}"
    })

    item = result.get("Item")
    if not item:
        return build_response(404, {"error": "Task not found"})

    log_event("get_task", user_id, task_id)
    return build_response(200, item)


@xray_recorder.capture("update_task")
def update_task(event, user_id):
    task_id = event["pathParameters"]["taskId"]
    body    = json.loads(event.get("body", "{}"))
    now     = datetime.now(timezone.utc).isoformat()

    updates      = []
    expr_names   = {"#upd": "updatedAt", "#st": "status"}
    expr_values  = {":upd": now}

    if "title" in body:
        updates.append("title = :title")
        expr_values[":title"] = body["title"]

    if "status" in body:
        updates.append("#st = :status, GSI1PK = :gsi1pk")
        expr_values[":status"] = body["status"]
        expr_values[":gsi1pk"] = f"STATUS#{body['status']}"

    if "description" in body:
        updates.append("description = :desc")
        expr_values[":desc"] = body["description"]

    if not updates:
        return build_response(400, {"error": "No valid fields to update"})

    update_expr = "SET #upd = :upd, " + ", ".join(updates)

    try:
        table.update_item(
            Key                       = {"PK": f"USER#{user_id}", "SK": f"TASK#{task_id}"},
            UpdateExpression          = update_expr,
            ExpressionAttributeNames  = expr_names,
            ExpressionAttributeValues = expr_values,
            ConditionExpression       = "attribute_exists(PK)"
        )
    except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
        return build_response(404, {"error": "Task not found"})

    log_event("update_task", user_id, task_id)
    return build_response(200, {"message": "Task updated"})


@xray_recorder.capture("delete_task")
def delete_task(event, user_id):
    task_id = event["pathParameters"]["taskId"]

    try:
        table.delete_item(
            Key               = {"PK": f"USER#{user_id}", "SK": f"TASK#{task_id}"},
            ConditionExpression = "attribute_exists(PK)"
        )
    except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
        return build_response(404, {"error": "Task not found"})

    log_event("delete_task", user_id, task_id)
    return build_response(200, {"message": "Task deleted"})


@xray_recorder.capture("generate_upload_url")
def generate_upload_url(event, user_id):
    """Generate a presigned S3 URL — client uploads directly to S3, not through Lambda."""
    task_id    = event["pathParameters"]["taskId"]
    params     = event.get("queryStringParameters") or {}
    file_name  = params.get("fileName", "attachment")
    content_type = params.get("contentType", "application/octet-stream")

    # Scope file path to user + task — prevents cross-user access
    s3_key = f"users/{user_id}/tasks/{task_id}/{file_name}"

    url = s3_client.generate_presigned_url(
        "put_object",
        Params     = {
            "Bucket":      BUCKET_NAME,
            "Key":         s3_key,
            "ContentType": content_type
        },
        ExpiresIn  = 300
    )

    log_event("generate_upload_url", user_id, task_id, {"s3Key": s3_key})
    return build_response(200, {"uploadUrl": url, "s3Key": s3_key, "expiresIn": 300})


def handler(event, context):
    """Main router — dispatches to the correct function based on HTTP method + path."""
    
    # DEBUG: Log the entire event to CloudWatch
    logger.info("=== DEBUG: FULL EVENT ===")
    logger.info(json.dumps(event, default=str))
    logger.info("=== DEBUG: END OF EVENT ===")
    
    # DEBUG: Check what's in authorizer
    authorizer = event.get("requestContext", {}).get("authorizer", {})
    logger.info(f"DEBUG: Authorizer object: {json.dumps(authorizer, default=str)}")
    
    claims = authorizer.get("claims", {})
    logger.info(f"DEBUG: Claims object: {json.dumps(claims, default=str)}")
    
    try:
        user_id = get_user_id(event)
    except ValueError as e:
        logger.error(f"DEBUG: Failed to get user_id - {str(e)}")
        return build_response(401, {"error": str(e), "debug": "No claims found in event"})

    method = event.get("httpMethod", "")
    path   = event.get("path", "")
    params = event.get("pathParameters") or {}

    logger.info(json.dumps({
        "requestId": context.aws_request_id,
        "method":    method,
        "path":      path,
        "userId":    user_id
    }))

    try:
        if method == "POST"   and path == "/tasks":                       return create_task(event, user_id)
        if method == "GET"    and path == "/tasks":                       return list_tasks(event, user_id)
        if method == "GET"    and params.get("taskId"):                   return get_task(event, user_id)
        if method == "PUT"    and params.get("taskId"):                   return update_task(event, user_id)
        if method == "DELETE" and params.get("taskId"):                   return delete_task(event, user_id)
        if method == "GET"    and path.endswith("/upload-url"):           return generate_upload_url(event, user_id)

        return build_response(404, {"error": "Route not found"})

    except Exception as e:
        logger.error(json.dumps({"error": str(e), "userId": user_id, "path": path}))
        return build_response(500, {"error": "Internal server error"})
