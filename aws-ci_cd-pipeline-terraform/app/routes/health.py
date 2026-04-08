import os
import boto3
from fastapi import APIRouter
from pydantic import BaseModel
from datetime import datetime, timezone

router = APIRouter()


class HealthResponse(BaseModel):
    status: str
    version: str
    environment: str
    timestamp: str
    checks: dict


@router.get("/health", response_model=HealthResponse)
async def health_check():
    checks = {}
    overall_status = "healthy"

    try:
        dynamodb = boto3.client(
            "dynamodb", region_name=os.environ.get("AWS_REGION", "us-east-1")
        )
        dynamodb.list_tables(Limit=1)
        checks["dynamodb"] = "healthy"
    except Exception as e:
        checks["dynamodb"] = f"unhealthy: {str(e)}"
        overall_status = "degraded"

    return HealthResponse(
        status=overall_status,
        version=os.environ.get("APP_VERSION", "unknown"),
        environment=os.environ.get("ENVIRONMENT", "unknown"),
        timestamp=datetime.now(timezone.utc).isoformat(),
        checks=checks,
    )


@router.get("/health/live")
async def liveness():
    return {"status": "alive"}


@router.get("/health/ready")
async def readiness():
    return {"status": "ready"}
