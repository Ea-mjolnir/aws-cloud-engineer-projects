import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from aws_xray_sdk.core import patch_all
from middleware.logging import LoggingMiddleware
from routes import health, tasks

patch_all()

app = FastAPI(
    title="Task Management API",
    version=os.environ.get("APP_VERSION", "1.0.0"),
    description="Production-grade API deployed via CI/CD on AWS ECS",
    docs_url="/docs" if os.environ.get("ENVIRONMENT") != "production" else None,
)

app.add_middleware(LoggingMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router, tags=["Health"])
app.include_router(tasks.router, tags=["Tasks"])
