"""
Gunicorn configuration for the Neal Street Rewards health app.

This file is referenced by the systemd unit: gunicorn --config gunicorn.conf.py app:app

Worker count: 2 * CPU + 1 is the Gunicorn recommendation. For a t3.micro
(2 vCPUs) that's 5, but we cap at 3 for dev to keep memory usage low.
In prod, tune based on instance type and load testing results.
"""

import multiprocessing
import os

# Bind to localhost only — Nginx reverse proxies to this socket
bind = "127.0.0.1:8000"

# Workers
workers = min(2 * multiprocessing.cpu_count() + 1, 3)
worker_class = "sync"
timeout = 30

# Logging — stdout/stderr, picked up by systemd journal → CloudWatch Agent
accesslog = "-"
errorlog = "-"
loglevel = os.environ.get("GUNICORN_LOG_LEVEL", "info")

# Security — limit request sizes to prevent abuse
limit_request_line = 4094
limit_request_fields = 50
limit_request_field_size = 8190

# Graceful shutdown — match ALB deregistration delay
graceful_timeout = 30

# Preload app for faster worker startup and shared memory
preload_app = True
