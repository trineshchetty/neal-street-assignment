"""
Neal Street Rewards — Health Endpoint Application

A minimal Flask application that serves a /health endpoint returning JSON
with deployment metadata. Designed to sit behind Gunicorn + Nginx.

The health endpoint:
  - Returns HTTP 200 with a JSON body for ALB health checks
  - Includes commit SHA (baked at deploy time by Ansible)
  - Includes AWS region (fetched from IMDSv2 at startup)
  - Includes secret consumption proof (demonstrates Secrets Manager integration)
  - Is the ONLY route — keeps the attack surface minimal

IMDSv2 is used exclusively (http_tokens=required on the instance). The app
fetches the region token once at startup, not per-request.
"""

import json
import logging
import os
import time

import boto3
import requests
from flask import Flask, jsonify

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

COMMIT_SHA = os.environ.get("COMMIT_SHA", "unknown")
SECRET_NAME = os.environ.get("SECRET_NAME", "")
AWS_REGION = os.environ.get("AWS_DEFAULT_REGION", "eu-west-1")
STARTUP_TIME = time.time()

# ---------------------------------------------------------------------------
# Logging — structured JSON to stdout, picked up by CloudWatch Agent
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("rewards-health")

# ---------------------------------------------------------------------------
# App Factory
# ---------------------------------------------------------------------------

app = Flask(__name__)


def _get_region_from_imds():
    """
    Fetch the AWS region from IMDSv2. Falls back to AWS_DEFAULT_REGION
    if IMDS is unreachable (e.g., running locally during development).

    IMDSv2 requires a PUT to get a session token first, then a GET with
    that token. The instance must have http_tokens=required.
    """
    try:
        token_resp = requests.put(
            "http://169.254.169.254/latest/api/token",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "300"},
            timeout=2,
        )
        token_resp.raise_for_status()
        token = token_resp.text

        az_resp = requests.get(
            "http://169.254.169.254/latest/meta-data/placement/availability-zone",
            headers={"X-aws-ec2-metadata-token": token},
            timeout=2,
        )
        az_resp.raise_for_status()
        # AZ is like "eu-west-1a", region is everything except the last char
        return az_resp.text[:-1]
    except Exception:
        logger.warning("IMDSv2 unavailable — using AWS_DEFAULT_REGION fallback")
        return AWS_REGION


def _get_secret_status():
    """
    Demonstrate Secrets Manager consumption. Retrieves the secret and returns
    a safe summary (key names only, never values) to prove the IAM integration
    works end-to-end.

    Returns a dict with 'available' bool and 'keys' list.
    """
    if not SECRET_NAME:
        return {"available": False, "reason": "SECRET_NAME not configured"}

    try:
        client = boto3.client("secretsmanager", region_name=REGION)
        response = client.get_secret_value(SecretId=SECRET_NAME)
        secret_data = json.loads(response["SecretString"])
        return {
            "available": True,
            "keys": sorted(secret_data.keys()),
        }
    except Exception as e:
        logger.error("Failed to retrieve secret: %s", str(e))
        return {"available": False, "reason": str(e)}


# Resolve region once at import time
REGION = _get_region_from_imds()
logger.info("Starting rewards-health | region=%s commit=%s", REGION, COMMIT_SHA)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@app.route("/health")
def health():
    """
    ALB health check endpoint. Returns 200 with deployment metadata.

    This is intentionally the only route. The response includes:
      - status: always "healthy" if the app is running
      - region: AWS region from IMDSv2
      - commit: git SHA baked at deploy time
      - uptime_seconds: how long the process has been running
      - secret: proof of Secrets Manager access (key names only)
    """
    return jsonify({
        "status": "healthy",
        "service": "neal-street-rewards",
        "region": REGION,
        "commit": COMMIT_SHA,
        "uptime_seconds": round(time.time() - STARTUP_TIME, 1),
        "secret": _get_secret_status(),
    })


# ---------------------------------------------------------------------------
# Local development entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=True)
