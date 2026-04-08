import os
import uuid
import boto3
import structlog
from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime, timezone
from boto3.dynamodb.conditions import Key

router = APIRouter()
logger = structlog.get_logger()

dynamodb = boto3.resource(
    "dynamodb", region_name=os.environ.get("AWS_REGION", "us-east-1")
)


def get_table():
    table_name = os.environ.get("DYNAMODB_TABLE", "tasks")
    return dynamodb.Table(table_name)


class TaskCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = Field(None, max_length=1000)
    priority: Optional[str] = Field("MEDIUM", pattern="^(LOW|MEDIUM|HIGH|CRITICAL)$")
    status: Optional[str] = Field("PENDING", pattern="^(PENDING|IN_PROGRESS|DONE)$")


class TaskUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=200)
    description: Optional[str] = Field(None, max_length=1000)
    priority: Optional[str] = Field(None, pattern="^(LOW|MEDIUM|HIGH|CRITICAL)$")
    status: Optional[str] = Field(None, pattern="^(PENDING|IN_PROGRESS|DONE)$")


@router.post("/tasks", status_code=201)
async def create_task(
    payload: TaskCreate,
    x_user_id: str = Header(
        ..., description="Authenticated user ID from upstream auth"
    ),
):
    task_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    item = {
        "PK": f"USER#{x_user_id}",
        "SK": f"TASK#{task_id}",
        "GSI1PK": f"STATUS#{payload.status}",
        "GSI1SK": f"CREATED#{now}",
        "taskId": task_id,
        "userId": x_user_id,
        "title": payload.title,
        "description": payload.description or "",
        "priority": payload.priority,
        "status": payload.status,
        "createdAt": now,
        "updatedAt": now,
    }

    get_table().put_item(Item=item)
    logger.info("task_created", task_id=task_id, user_id=x_user_id)
    return {"taskId": task_id, "message": "Task created successfully"}


@router.get("/tasks")
async def list_tasks(x_user_id: str = Header(...), status: Optional[str] = None):
    if status:
        result = get_table().query(
            IndexName="StatusIndex",
            KeyConditionExpression=Key("GSI1PK").eq(f"STATUS#{status}"),
            FilterExpression="userId = :uid",
            ExpressionAttributeValues={":uid": x_user_id},
        )
    else:
        result = get_table().query(
            KeyConditionExpression=Key("PK").eq(f"USER#{x_user_id}")
            & Key("SK").begins_with("TASK#")
        )

    return {"tasks": result["Items"], "count": len(result["Items"])}


@router.get("/tasks/{task_id}")
async def get_task(task_id: str, x_user_id: str = Header(...)):
    result = get_table().get_item(
        Key={"PK": f"USER#{x_user_id}", "SK": f"TASK#{task_id}"}
    )
    item = result.get("Item")
    if not item:
        raise HTTPException(status_code=404, detail="Task not found")
    return item


@router.put("/tasks/{task_id}")
async def update_task(task_id: str, payload: TaskUpdate, x_user_id: str = Header(...)):
    updates = []
    expr_names = {"#upd": "updatedAt"}
    expr_values = {":upd": datetime.now(timezone.utc).isoformat()}

    if payload.title is not None:
        updates.append("title = :title")
        expr_values[":title"] = payload.title

    if payload.status is not None:
        updates.append("#st = :status, GSI1PK = :gsi1pk")
        expr_names["#st"] = "status"
        expr_values[":status"] = payload.status
        expr_values[":gsi1pk"] = f"STATUS#{payload.status}"

    if payload.description is not None:
        updates.append("description = :desc")
        expr_values[":desc"] = payload.description

    if payload.priority is not None:
        updates.append("priority = :priority")
        expr_values[":priority"] = payload.priority

    if not updates:
        raise HTTPException(status_code=400, detail="No valid fields to update")

    try:
        get_table().update_item(
            Key={"PK": f"USER#{x_user_id}", "SK": f"TASK#{task_id}"},
            UpdateExpression="SET #upd = :upd, " + ", ".join(updates),
            ExpressionAttributeNames=expr_names,
            ExpressionAttributeValues=expr_values,
            ConditionExpression="attribute_exists(PK)",
        )
    except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
        raise HTTPException(status_code=404, detail="Task not found")

    return {"message": "Task updated"}


@router.delete("/tasks/{task_id}", status_code=204)
async def delete_task(task_id: str, x_user_id: str = Header(...)):
    try:
        get_table().delete_item(
            Key={"PK": f"USER#{x_user_id}", "SK": f"TASK#{task_id}"},
            ConditionExpression="attribute_exists(PK)",
        )
    except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
        raise HTTPException(status_code=404, detail="Task not found")
