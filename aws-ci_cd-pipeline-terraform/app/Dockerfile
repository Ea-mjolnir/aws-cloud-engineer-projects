# ─── Stage 1: Build dependencies ─────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

# Install build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# Install to a local directory so we can copy cleanly to final stage
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ─── Stage 2: Production image ───────────────────────────────────────────────
FROM python:3.12-slim AS production

# Security: run as non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

# Copy only built packages from builder stage — no gcc, no build tools
COPY --from=builder /install /usr/local

# Copy application code
COPY --chown=appuser:appuser . .

# Security hardening
RUN chmod -R 550 /app && \
    find /app -type f -name "*.py" -exec chmod 440 {} \;

USER appuser

# Metadata labels — visible in ECR and ECS
ARG APP_VERSION=unknown
ARG BUILD_DATE=unknown
ARG GIT_COMMIT=unknown

LABEL org.opencontainers.image.version=$APP_VERSION \
      org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.revision=$GIT_COMMIT \
      org.opencontainers.image.title="task-management-api"

ENV APP_VERSION=$APP_VERSION \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health/live')"

CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", \
     "--port", "8080", \
     "--workers", "2", \
     "--access-log", \
     "--log-level", "info"]
