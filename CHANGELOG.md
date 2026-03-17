# Changelog

All notable changes to the Neal Street dev web tier project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## Phase 11 — Documentation

### Added
- **README.md** — complete project documentation:
  - Architecture diagram (ASCII)
  - Prerequisites table with tool versions and install commands
  - Quick start guide (bootstrap → provision → configure → verify → access)
  - CI/CD workflow summary and required GitHub Secrets
  - Project structure tree
  - Cleanup instructions with cost note (NAT Gateway + ALB as primary cost drivers)
  - Tags table
- **SOLUTION.md** — design decisions and trade-offs as required by the assignment:
  - Task 1: Terraform architecture decisions (ALB + private subnets, single AZ, IMDSv2, no SSH)
  - State handling trade-offs (S3+DynamoDB vs Terraform Cloud vs local vs Git backend)
  - Module design and circular dependency avoidance
  - Cost profile table (~$57/month for dev)
  - Task 2: Ansible role design, inventory strategy, secrets handling flow
  - Task 3: CI/CD pipeline design (OIDC federation, concurrency controls, plan artifacts)
  - Prod promotion procedure (6 steps: directory, multi-AZ, HTTPS, credential separation, workflow, observability)
  - Stretch goals summary table
  - AWS Well-Architected Framework alignment across all 5 pillars

---

## Phase 10 — GitHub Actions CI/CD Pipeline

### Added
- **CI workflow** (`.github/workflows/ci.yml`) — runs on every push and PR, 4 parallel jobs:
  - **Terraform Validate** — `fmt -check -recursive` + `init -backend=false` + `validate` for backend and dev environment
  - **Ansible Lint** — `yamllint` + `ansible-lint` against site playbook and all roles
  - **Python Lint** — `flake8` on Flask app with 120 char line length
  - **Security Scan** — `tfsec` + `checkov` for Terraform security misconfigurations (open SGs, unencrypted resources, missing logging)
- **Deploy workflow** (`.github/workflows/deploy.yml`) — runs on push to main or manual trigger, 3 sequential jobs:
  - **Terraform Plan** — generates plan, uploads as artifact for audit trail
  - **Terraform Apply** — downloads plan artifact, applies (no re-plan drift risk)
  - **Ansible Configure** — runs site playbook with `commit_sha` from `${{ github.sha }}`
- **OIDC federation** — `id-token: write` permission, `aws-actions/configure-aws-credentials@v4` with role assumption, no long-lived access keys
- **Concurrency controls** — CI cancels in-progress on same branch, deploy never cancels (prevents half-applied state)
- **GitHub Environments** — `dev` environment referenced in deploy jobs, ready for protection rules (approval gates for prod)
- **Pinned action versions** — all third-party actions use specific versions for supply chain security

---

## Phase 9 — Ansible Observability Role

### Added
- **Observability role** (`ansible/roles/observability/`) — installs and configures CloudWatch Agent for centralized log shipping and custom metrics
- **CloudWatch Agent install** — from Amazon Linux 2023 default repos, no S3 download or third-party repos needed
- **Agent configuration** (`cloudwatch-agent-config.json.j2`) — templated JSON with environment-specific log group names:
  - **System logs** → `/<project>/<env>/system` log group:
    - `/var/log/messages` — general system logs
    - `/var/log/secure` — authentication/authorization events
    - `/var/log/audit/audit.log` — auditd output (from security baseline role)
  - **Application logs** → `/<project>/<env>/app` log group:
    - `/var/log/nginx/access.log` — HTTP request logs
    - `/var/log/nginx/error.log` — Nginx errors and upstream failures
  - Log streams keyed by `{instance_id}` — queryable per-instance in CloudWatch Logs Insights
- **Custom metrics** — published to `NealStreet/<app_name>` namespace:
  - Memory: `mem_used_percent`, `mem_available_percent` (not available from default EC2 metrics)
  - Disk: `disk_used_percent` on root volume
  - CPU: `cpu_usage_idle`, `cpu_usage_user`, `cpu_usage_system`
  - Dimensions: `InstanceId`, `AutoScalingGroupName` for filtering
- **Agent management** — uses `amazon-cloudwatch-agent-ctl` (not systemctl) as required by the agent
- **Site playbook** updated — `observability` role added as third role after `security_baseline` and `app_deploy`

---

## Phase 8 — Ansible App Deployment Role

### Added
- **App deployment role** (`ansible/roles/app_deploy/`) — deploys Flask + Gunicorn + Nginx reverse proxy stack
- **Service user** — dedicated `rewards` system user with `/sbin/nologin` shell, no home directory, owns only `/opt/rewards` (limits blast radius on compromise)
- **Python venv** — isolated virtual environment prevents system Python pollution, `pip install` from pinned `requirements.txt`
- **Code deployment** — copies `app.py`, `gunicorn.conf.py`, `requirements.txt` to `/opt/rewards`, templates `.env` file with `COMMIT_SHA`, `SECRET_NAME`, `AWS_DEFAULT_REGION`
- **Gunicorn systemd unit** — `Type=notify`, `Restart=on-failure` with rate limiting (5 restarts in 60s), graceful shutdown matching ALB deregistration (30s), systemd sandboxing (`ProtectSystem=full`, `ProtectHome=true`, `PrivateTmp=true`, `NoNewPrivileges=true`)
- **Nginx reverse proxy** — upstream with keepalive, security headers (X-Content-Type-Options, X-Frame-Options, X-XSS-Protection, Referrer-Policy), `server_tokens off`, request size/timeout limits, only `/health` proxied (everything else returns 404), dotfiles blocked
- **Env file** — permissions `0600`, contains runtime config injected by Ansible variables (commit SHA from CI, secret name from Terraform output)
- **Handlers** — systemd daemon-reload, conditional Gunicorn/Nginx restarts
- **Site playbook** updated — `app_deploy` role added after `security_baseline`

---

## Phase 7 — Ansible Security Baseline Role

### Added
- **Ansible project scaffold** (`ansible/`) — `ansible.cfg`, dynamic inventory, site playbook
- **AWS EC2 dynamic inventory** (`ansible/inventory/aws_ec2.yml`) — discovers instances by tags, no static IPs to maintain, uses SSM connection plugin
- **Site playbook** (`ansible/site.yml`) — orchestrates roles in order with tag-based selective execution
- **Security baseline role** (`ansible/roles/security_baseline/`) — OS hardening for Amazon Linux 2023:
  - **Patching** — full package update, security tooling install (fail2ban, aide, audit), dnf-automatic for ongoing security-only patches
  - **SSH hardening** — defence in depth (root login disabled, password auth off, max auth tries 3, client alive intervals, X11 forwarding off) with `sshd -t` validation before apply
  - **Kernel hardening** — sysctl tunables aligned with CIS Benchmark: IP spoofing prevention, source routing disabled, ICMP redirect rejection, SYN flood protection, IPv6 disabled
  - **Audit daemon** — auditd rules monitoring auth events, privilege escalation (sudo/su), file integrity on critical paths (/etc/passwd, /etc/shadow, sshd_config), cron changes, network config changes. Rules made immutable (`-e 2`)
- **Handlers** — conditional service restarts (sshd, auditd, dnf-automatic) only triggered on actual changes

---

## Phase 6 — Flask Health Application

### Added
- **Flask health app** (`app/`) — minimal application serving `/health` endpoint behind Gunicorn + Nginx
- **`app.py`** — single-route Flask app returning JSON with deployment metadata:
  - `status` — always "healthy" if the process is running
  - `region` — fetched from IMDSv2 at startup (not per-request), falls back to `AWS_DEFAULT_REGION`
  - `commit` — git SHA injected as `COMMIT_SHA` env var by Ansible at deploy time
  - `uptime_seconds` — process uptime for debugging restart loops
  - `secret` — demonstrates Secrets Manager consumption (returns key names only, never values)
- **IMDSv2 exclusively** — PUT for session token, GET with token header, matches `http_tokens = required` on the instance
- **`gunicorn.conf.py`** — production-grade Gunicorn configuration:
  - Binds to `127.0.0.1:8000` (Nginx reverse proxy only, not directly exposed)
  - Worker count: `min(2 * CPU + 1, 3)` — capped for dev memory constraints
  - Request size limits to prevent abuse
  - Graceful timeout matches ALB deregistration delay (30s)
  - `preload_app = True` for shared memory and faster worker startup
- **`requirements.txt`** — pinned versions: Flask 3.1.1, Gunicorn 23.0.0, boto3 1.38.23
- **Structured logging** — JSON-formatted to stdout, ready for CloudWatch Agent pickup

---

## Phase 5 — Secrets & Observability

### Added
- **Secrets module** (`terraform/modules/secrets/`) — AWS Secrets Manager secret with sample JSON payload
  - 7-day recovery window for accidental deletion protection
  - `ignore_changes` lifecycle on secret value — prevents Terraform from overwriting rotation/manual updates
  - Comments document prod path: KMS CMK, automatic rotation via Lambda, cross-account resource policies
- **Observability module** (`terraform/modules/observability/`) — centralized logging and ALB health alarms
  - **App log group** (`/<project>/<env>/app`) — for Gunicorn/Flask application logs
  - **System log group** (`/<project>/<env>/system`) — for syslog/secure logs
  - Configurable retention (7 days dev, 30-90 days prod)
  - **Unhealthy hosts alarm** — fires when HealthyHostCount < 1, `treat_missing_data = breaching` (safe default)
  - **ELB 5xx alarm** — fires on > 10 server errors in 5 minutes, `treat_missing_data = notBreaching`
  - Alarm actions wired to optional SNS topic (silent in dev, PagerDuty/Slack in prod)
- **Loadbalancer module outputs** — added `alb_arn_suffix` and `target_group_arn_suffix` for CloudWatch metric dimensions
- **Compute module wiring** — now receives `secrets_manager_arn` and `cloudwatch_log_group_name` from sibling modules
- **Dev environment outputs** — `secret_arn` (sensitive), `secret_name`, `app_log_group_name`, `system_log_group_name`

---

## Phase 4 — Load Balancer Module

### Added
- **Load balancer module** (`terraform/modules/loadbalancer/`) — public-facing ALB with target group and HTTP listener
- **ALB** — `drop_invalid_header_fields = true` (AWS Well-Architected security recommendation to prevent HTTP request smuggling)
- **Target group** — health check on `/health` expecting HTTP 200, deregistration delay reduced to 30s for faster dev deployments (300s recommended for prod)
- **Target group attachments** — dynamically registers EC2 instances via `count`, scales automatically with `instance_count`
- **HTTP listener** — forwards to target group on port 80 (prod should add HTTPS listener with ACM cert and HTTP→HTTPS redirect)
- **Dev environment outputs** — `alb_dns_name` (primary access point) and `target_group_arn`

---

## Phase 3 — Compute Module

### Added
- **Compute module** (`terraform/modules/compute/`) — EC2 instances behind a launch template
- **AMI data source** — auto-selects latest Amazon Linux 2023 with optional override for golden AMI pipelines
- **Launch template** — IMDSv2 enforced (`http_tokens = required`), encrypted gp3 EBS root volume, detailed monitoring enabled, no SSH key pair
- **EC2 security group** — ingress restricted to ALB security group on app port only, no port 22 open
- **IAM instance profile** with least-privilege policies:
  - `AmazonSSMManagedInstanceCore` for SSM Session Manager (replaces SSH entirely)
  - `CloudWatchAgentServerPolicy` for log shipping and metrics
  - Inline policy scoped to a specific Secrets Manager ARN for app secret access
- **ALB security group** defined in `terraform/environments/dev/main.tf` — shared reference between load balancer and compute modules to avoid circular dependencies
- **Compute variables** added to dev environment: `instance_type` (t3.micro), `instance_count` (1), `app_port` (80)

---

## Phase 2 — Networking Module

### Added
- **Networking module** (`terraform/modules/networking/`) — full VPC stack for a single-AZ dev topology
- **VPC** — `/16` CIDR, DNS support and hostnames enabled (required for SSM and VPC endpoints)
- **Public subnet** — hosts the ALB, `map_public_ip_on_launch = false`
- **Private subnet** — hosts EC2 instances, fully isolated from direct internet access
- **Internet Gateway** — provides internet access for the public subnet
- **NAT Gateway + Elastic IP** — outbound-only internet for the private subnet (package installs, CloudWatch Agent, SSM connectivity)
- **Route tables** — public routes via IGW, private routes via NAT Gateway
- **VPC Flow Logs** — captures REJECT traffic to CloudWatch Logs with 7-day retention for security auditing
- **Dev environment configuration** (`terraform/environments/dev/`):
  - `providers.tf` — AWS provider with `default_tags` block for automatic tag inheritance
  - `backend.tf` — S3 remote state with per-environment key isolation
  - `main.tf` — module composition entry point
  - `terraform.tfvars` — dev-specific values
  - `outputs.tf` — VPC and subnet IDs

---

## Phase 1 — Project Scaffold & Terraform Backend Bootstrap

### Added
- **Project scaffold** — directory structure for Terraform modules, environments, Ansible roles, and GitHub Actions
- **`.gitignore`** — covers Terraform state/plans, sensitive tfvars, Ansible retry files, Python cache, env files, IDE configs
- **Terraform state backend** (`terraform/backend/`):
  - S3 bucket with versioning enabled for state file recovery
  - KMS server-side encryption with bucket key for cost efficiency
  - Public access block on all four settings
  - `prevent_destroy` lifecycle rule to guard against accidental deletion
  - DynamoDB table (`PAY_PER_REQUEST`) for state locking to prevent concurrent applies
