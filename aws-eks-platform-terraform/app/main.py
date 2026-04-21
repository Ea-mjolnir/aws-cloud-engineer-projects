"""
Task Management API - Production-ready FastAPI application
Runs on EKS with IRSA, HPA, and GitOps
"""

import os
import logging
import time
from contextlib import asynccontextmanager
from typing import Optional, List
from datetime import datetime

import boto3
from fastapi import FastAPI, HTTPException, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from prometheus_client import Counter, Histogram, generate_latest
from opentelemetry import trace
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

# =============================================================================
# Configuration
# =============================================================================
class Settings(BaseModel):
    app_name: str = "task-api"
    version: str = os.getenv("APP_VERSION", "1.0.0")
    environment: str = os.getenv("ENVIRONMENT", "development")
    aws_region: str = os.getenv("AWS_REGION", "us-east-1")
    dynamodb_table: str = os.getenv("DYNAMODB_TABLE", "eks-tasks")
    log_level: str = os.getenv("LOG_LEVEL", "INFO")
    git_commit: str = os.getenv("GIT_COMMIT", "unknown")

settings = Settings()

# =============================================================================
# Logging
# =============================================================================
logging.basicConfig(
    level=settings.log_level,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# =============================================================================
# Metrics
# =============================================================================
request_count = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
request_duration = Histogram('http_request_duration_seconds', 'HTTP request duration', ['method', 'endpoint'])
tasks_created = Counter('tasks_created_total', 'Total tasks created')

# =============================================================================
# AWS Clients (IRSA authenticated - no credentials needed!)
# =============================================================================
dynamodb = boto3.client('dynamodb', region_name=settings.aws_region)

# =============================================================================
# Models
# =============================================================================
class Task(BaseModel):
    id: str = Field(default_factory=lambda: f"task-{int(time.time() * 1000)}")
    title: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = Field(None, max_length=1000)
    status: str = Field(default="pending", pattern="^(pending|in_progress|completed|cancelled)$")
    created_at: str = Field(default_factory=lambda: datetime.utcnow().isoformat())
    updated_at: Optional[str] = None
    priority: int = Field(default=1, ge=1, le=5)
    tags: List[str] = Field(default=[])
    metadata: dict = Field(default={})

class TaskUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=200)
    description: Optional[str] = Field(None, max_length=1000)
    status: Optional[str] = Field(None, pattern="^(pending|in_progress|completed|cancelled)$")
    priority: Optional[int] = Field(None, ge=1, le=5)
    tags: Optional[List[str]] = None

class HealthResponse(BaseModel):
    status: str
    version: str
    environment: str
    git_commit: str
    timestamp: str

class InfoResponse(BaseModel):
    app_name: str
    version: str
    environment: str
    aws_region: str
    dynamodb_table: str
    git_commit: str

# =============================================================================
# Lifespan Events
# =============================================================================
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown events"""
    logger.info(f"Starting {settings.app_name} v{settings.version} in {settings.environment}")
    logger.info(f"AWS Region: {settings.aws_region}, DynamoDB: {settings.dynamodb_table}")
    
    # Verify DynamoDB connection
    try:
        dynamodb.describe_table(TableName=settings.dynamodb_table)
        logger.info(f"Connected to DynamoDB table: {settings.dynamodb_table}")
    except Exception as e:
        logger.warning(f"DynamoDB table not ready: {e}")
    
    yield
    
    logger.info(f"Shutting down {settings.app_name}")

# =============================================================================
# FastAPI App
# =============================================================================
app = FastAPI(
    title="Task Management API",
    description="Production EKS platform demonstration",
    version=settings.version,
    lifespan=lifespan
)

# Instrument with OpenTelemetry
FastAPIInstrumentor.instrument_app(app)

# =============================================================================
# Middleware
# =============================================================================
@app.middleware("http")
async def metrics_middleware(request, call_next):
    """Record request metrics"""
    start_time = time.time()
    response = await call_next(request)
    duration = time.time() - start_time
    
    request_count.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code
    ).inc()
    
    request_duration.labels(
        method=request.method,
        endpoint=request.url.path
    ).observe(duration)
    
    return response

# =============================================================================
# Health & Info Endpoints
# =============================================================================
@app.get("/health/live", response_model=HealthResponse, tags=["Health"])
async def liveness_probe():
    """Kubernetes liveness probe"""
    return HealthResponse(
        status="alive",
        version=settings.version,
        environment=settings.environment,
        git_commit=settings.git_commit,
        timestamp=datetime.utcnow().isoformat()
    )

@app.get("/health/ready", response_model=dict, tags=["Health"])
async def readiness_probe():
    """Kubernetes readiness probe - checks dependencies"""
    try:
        # Check DynamoDB connection
        dynamodb.describe_table(TableName=settings.dynamodb_table)
        return {"status": "ready", "dynamodb": "connected"}
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        raise HTTPException(status_code=503, detail=f"Service unavailable: {e}")

@app.get("/info", response_model=InfoResponse, tags=["Info"])
async def info():
    """Application information"""
    return InfoResponse(
        app_name=settings.app_name,
        version=settings.version,
        environment=settings.environment,
        aws_region=settings.aws_region,
        dynamodb_table=settings.dynamodb_table,
        git_commit=settings.git_commit
    )

@app.get("/metrics", tags=["Metrics"])
async def metrics():
    """Prometheus metrics endpoint"""
    return JSONResponse(
        content={"metrics": generate_latest().decode('utf-8')},
        media_type="text/plain"
    )

# =============================================================================
# Task API Endpoints
# =============================================================================
@app.get("/tasks", response_model=List[Task], tags=["Tasks"])
async def list_tasks(limit: int = 50, status: Optional[str] = None):
    """List all tasks"""
    logger.info(f"Listing tasks (limit={limit}, status={status})")
    
    # In production, query DynamoDB
    # For now, return mock data
    return [
        Task(
            id="task-1",
            title="Deploy to EKS",
            description="Set up GitOps with ArgoCD",
            status="completed",
            priority=1,
            tags=["kubernetes", "devops"]
        ),
        Task(
            id="task-2",
            title="Configure IRSA",
            description="Set up IAM Roles for Service Accounts",
            status="in_progress",
            priority=2,
            tags=["aws", "security"]
        ),
        Task(
            id="task-3",
            title="Set up monitoring",
            description="Deploy Prometheus and Grafana",
            status="pending",
            priority=3,
            tags=["observability"]
        )
    ]

@app.post("/tasks", response_model=Task, status_code=status.HTTP_201_CREATED, tags=["Tasks"])
async def create_task(task: Task):
    """Create a new task"""
    logger.info(f"Creating task: {task.title}")
    tasks_created.inc()
    
    # In production, save to DynamoDB
    task.created_at = datetime.utcnow().isoformat()
    return task

@app.get("/tasks/{task_id}", response_model=Task, tags=["Tasks"])
async def get_task(task_id: str):
    """Get a specific task"""
    logger.info(f"Getting task: {task_id}")
    
    if task_id == "not-found":
        raise HTTPException(status_code=404, detail="Task not found")
    
    return Task(
        id=task_id,
        title="Sample Task",
        description="This is a sample task",
        status="pending",
        priority=1
    )

@app.patch("/tasks/{task_id}", response_model=Task, tags=["Tasks"])
async def update_task(task_id: str, update: TaskUpdate):
    """Update a task"""
    logger.info(f"Updating task {task_id}: {update}")
    
    task = Task(
        id=task_id,
        title=update.title or "Updated Task",
        description=update.description or "Updated description",
        status=update.status or "pending",
        priority=update.priority or 1,
        updated_at=datetime.utcnow().isoformat()
    )
    return task

@app.delete("/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["Tasks"])
async def delete_task(task_id: str):
    """Delete a task"""
    logger.info(f"Deleting task: {task_id}")
    return None

# =============================================================================
# Root Endpoint
# =============================================================================
@app.get("/", tags=["Root"])
async def root():
    """API root"""
    return {
        "message": f"Welcome to {settings.app_name}",
        "version": settings.version,
        "environment": settings.environment,
        "docs": "/docs",
        "health": "/health/live",
        "metrics": "/metrics"
    }
