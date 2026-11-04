# syntax=docker/dockerfile:1
FROM python:3.12-slim

# Prevent Python from writing .pyc files and buffering stdout/stderr
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Inject version at build time so app version and container tag always match
ARG APP_VERSION=0.1.0-dev
ENV APP_VERSION=${APP_VERSION}

WORKDIR /app

# Create a non-root user for production security
RUN groupadd --gid 10001 appgroup && \
    useradd --uid 10001 --gid appgroup --shell /sbin/nologin --no-create-home appuser

COPY --chown=appuser:appgroup hello_world.py .

USER appuser

ENTRYPOINT ["python", "hello_world.py"]
