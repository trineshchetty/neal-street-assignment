# SOLUTION.md — Design Decisions and Trade-offs

## Overview

This project implements a production-shaped dev web tier for Neal Street Technologies' rewards platform. The design prioritises operational maturity, security posture, and a clear promotion path to production — while staying within the single-AZ, low-cost constraints of the assignment.

**Mandatory observability path chosen:** Centralized logs (CloudWatch Logs via CloudWatch Agent).
**Stretch goal implemented:** Basic metrics/alarms (HealthyHostCount, ELB 5xx, custom memory/disk/CPU metrics).

---

## Task 1: Terraform — Infrastructure Design

### Architecture Decisions

#### ALB + EC2 in Private Subnets
- **Decision:** Application Load Balancer in the public subnet, EC2 instances in the private subnet with no public IP.
- **Why:** The assignment requires "application servers run on Linux in protected subnets." Private subnets with NAT Gateway provide outbound-only internet access (for package installs, CloudWatch Agent, SSM), while the ALB handles all inbound traffic.
- **Trade-off:** NAT Gateway costs ~$0.045/hr even when idle. For dev, VPC endpoints for SSM/CloudWatch/S3 would eliminate this cost but add module complexity. NAT Gateway was chosen for simplicity within the time box.

#### Single AZ Topology
- **Decision:** One public subnet + one private subnet in `eu-west-1a`.
- **Why:** The assignment explicitly permits single-AZ for dev. Multi-AZ would require a second set of subnets and a second NAT Gateway (doubling cost).
- **Prod promotion:** Add subnets in `eu-west-1b` and `eu-west-1c`, convert subnet variables to lists, and update the ALB to span all three AZs. The module design supports this — `public_subnet_ids` is already a list.

#### IMDSv2 Enforced
- **Decision:** `http_tokens = required` on all EC2 instances.
- **Why:** IMDSv1 is vulnerable to SSRF attacks that can steal IAM credentials. IMDSv2 requires a PUT request with a TTL-bound token, which mitigates this class of attack. This is an AWS Well-Architected Framework security pillar recommendation.

#### No SSH — SSM Session Manager Only
- **Decision:** Port 22 is not open in any security group. No SSH key pair is associated with instances.
- **Why:** SSM Session Manager provides shell access with full CloudTrail audit logging, no bastion host, no key management overhead, and no inbound ports from the internet. The Ansible `aws_ssm` connection plugin enables configuration management over the same channel.
- **Trade-off:** Requires the SSM agent (pre-installed on Amazon Linux 2023) and an IAM instance profile with `AmazonSSMManagedInstanceCore`. Slightly more complex initial setup vs SSH, but operationally superior.

### State Handling

#### Approach: S3 + DynamoDB

- **S3 bucket** with versioning enabled — provides state file history for recovery if state is corrupted.
- **KMS encryption** — state files contain resource metadata (ARNs, IPs) that should be encrypted at rest.
- **DynamoDB table** for state locking — prevents concurrent `terraform apply` operations from corrupting state. Uses `PAY_PER_REQUEST` billing (no provisioned capacity cost for dev).
- **Per-environment key isolation** — each environment uses a separate S3 key path (`dev/terraform.tfstate`, `prod/terraform.tfstate`), enabling independent state management while sharing one bucket.

#### Trade-offs Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| **S3 + DynamoDB** | Team-safe locking, versioned recovery, encrypted, free tier eligible | Requires bootstrap step, DynamoDB cost (minimal with PAY_PER_REQUEST) | **Chosen** |
| **Terraform Cloud** | Built-in locking, UI, run history | Vendor lock-in, free tier limits (5 users), adds external dependency | Rejected |
| **Local state** | Zero setup | No locking, no team collaboration, state loss if machine fails | Rejected |
| **GitLab/GH backend** | No extra infra | No locking, state in git history is a security risk | Rejected |

#### Bootstrap Chicken-and-Egg

The state backend resources (S3 bucket, DynamoDB table) are managed in a separate Terraform configuration (`terraform/backend/`) with local state. This avoids the circular dependency of "where does the state for the state backend live?" The backend config uses `prevent_destroy` lifecycle rules to guard against accidental deletion.

### Module Design

The infrastructure is split into 5 modules, each with a single responsibility:

| Module | Responsibility | Key outputs consumed by |
|--------|---------------|------------------------|
| `networking` | VPC, subnets, NAT, IGW, flow logs | `compute`, `loadbalancer` |
| `compute` | EC2, launch template, IAM, SG | `loadbalancer` |
| `loadbalancer` | ALB, target group, listener | `observability` |
| `secrets` | Secrets Manager secret | `compute` (IAM policy) |
| `observability` | CloudWatch log groups, alarms | `compute` (log group name) |

**Circular dependency avoidance:** The ALB security group is defined in the environment composition layer (`environments/dev/main.tf`), not in either the compute or loadbalancer module. Both modules reference it by ID, avoiding a circular dependency.

### Tags

All resources receive consistent tags via a `common_tags` local that flows through every module. The AWS provider also has `default_tags` configured for automatic tag inheritance on resources that support it.

```hcl
environment = "dev"
service     = "rewards"
owner       = "candidate"
cost_center = "payments"
project     = "neal-street"
```

### Cost Profile (dev)

| Resource | Hourly Cost | Monthly Estimate |
|----------|-------------|-----------------|
| NAT Gateway | $0.045 | ~$32.40 |
| ALB | $0.0225 | ~$16.20 |
| t3.micro EC2 | $0.0104 | ~$7.49 (free tier eligible) |
| Secrets Manager | — | ~$0.40/secret |
| CloudWatch Logs | — | ~$0.50/GB ingested |
| **Total** | | **~$57/month** |

**To minimise costs:** Run `terraform destroy` when not actively testing. The NAT Gateway and ALB are the primary cost drivers.

---

## Task 2: Ansible — Configuration Management

### Role Design

Three roles execute in order, each with a specific purpose:

#### 1. `security_baseline` — OS Hardening
- **Patching:** Full `dnf update`, security package install (fail2ban, aide, audit), `dnf-automatic` for ongoing security patches.
- **SSH hardening:** Defence in depth — root login disabled, password auth off, max auth tries 3. Every change validated with `sshd -t` before applying (prevents lockouts from bad config).
- **Kernel hardening:** 12 sysctl tunables aligned with CIS Amazon Linux 2023 Benchmark — IP spoofing prevention, ICMP redirect rejection, SYN flood protection.
- **Audit daemon:** Rules monitoring auth events, privilege escalation, file integrity on critical paths. Ruleset made immutable (`-e 2`).

**Why defence in depth on SSH if port 22 is closed?** Security groups can be misconfigured. Compliance frameworks (CIS, SOC2) require SSH hardening regardless of network controls. If SSM is ever unavailable, emergency SSH access should already be hardened.

#### 2. `app_deploy` — Application Stack
- **Service user:** Dedicated `rewards` user with `/sbin/nologin`, no home directory. Limits blast radius on compromise.
- **Python venv:** Isolated dependencies, no system pip pollution.
- **Gunicorn systemd unit:** `Type=notify`, restart-on-failure with rate limiting, systemd sandboxing (`ProtectSystem=full`, `PrivateTmp=true`, `NoNewPrivileges=true`).
- **Nginx reverse proxy:** Security headers, only `/health` proxied (everything else 404), dotfiles blocked, server tokens off.
- **Environment file:** `.env` with `0600` permissions contains `COMMIT_SHA`, `SECRET_NAME`, `AWS_DEFAULT_REGION`.

**Why Gunicorn + Nginx instead of just one?** Nginx handles connection buffering (protects Gunicorn from slow clients), security headers, and serves as the entry point for ALB health checks. Gunicorn handles Python WSGI process management. This is the standard production pattern.

#### 3. `observability` — CloudWatch Agent
- **Log collection:** 5 log sources shipped to Terraform-created log groups (messages, secure, audit, nginx-access, nginx-error).
- **Custom metrics:** Memory, disk, CPU in a `NealStreet/rewards-health` namespace — these metrics are not available from default EC2 monitoring.
- **Log streams keyed by instance ID:** Enables per-instance querying in CloudWatch Logs Insights.

### Inventory Strategy

**Dynamic inventory** via the `amazon.aws.aws_ec2` plugin. Instances are discovered by tags (`project=neal-street`, `instance-state-name=running`) and grouped by `environment` and `service` tags. When instances are replaced or scaled, Ansible picks them up automatically — zero inventory file changes.

**Connection:** `aws_ssm` plugin, matching the no-SSH approach from Terraform. No SSH keys to distribute or manage.

### Secrets Handling

Secrets are **never written to disk** on the instance. The flow:
1. Terraform creates the Secrets Manager secret and outputs its name.
2. Ansible templates the secret name (not value) into the app's `.env` file.
3. At runtime, the Flask app uses `boto3` to call `GetSecretValue` via the instance's IAM role.
4. The `/health` endpoint proves the integration works by returning the secret's key names (never values).

---

## Task 3: CI/CD Pipeline

### Pipeline Design

Two workflows with distinct triggers:

| Workflow | Trigger | Jobs |
|----------|---------|------|
| **CI** | Push/PR to any branch | Terraform validate, Ansible lint, Python lint, Security scan (tfsec + checkov) |
| **Deploy** | Push to main / manual | Terraform plan → apply → Ansible configure |

### Key Decisions

#### OIDC Federation (No Long-Lived Keys)
- **Decision:** AWS credentials via `aws-actions/configure-aws-credentials@v4` with `role-to-assume`.
- **Why:** OIDC federation produces short-lived STS tokens per workflow run. No `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` stored in GitHub Secrets. Tokens expire automatically — no rotation needed.
- **Setup:** Create an IAM OIDC identity provider for `token.actions.githubusercontent.com`, then create a role with a trust policy scoping to the specific repository and branch.

#### Concurrency Controls
- **CI:** `cancel-in-progress: true` — if you push twice quickly, the first run is cancelled. Saves runner minutes.
- **Deploy:** `cancel-in-progress: false` — never cancel an in-progress deploy. A half-applied Terraform state is the worst failure mode.

#### Plan Artifact
- **Decision:** `terraform plan -out=tfplan` uploaded as an artifact, downloaded by the apply job.
- **Why:** The apply uses the exact plan that was generated — no re-plan that might pick up changes that landed between plan and apply. This eliminates drift between "what was reviewed" and "what was applied."

#### Security Scanning
- **tfsec** and **checkov** run as `soft_fail: true` — they report issues but don't block the pipeline.
- **Why:** These tools are opinionated and may flag intentional choices (e.g., HTTP listener without HTTPS). Blocking on false positives slows velocity. The findings are visible in the PR for human review.

---

## Prod Promotion Procedure

### Step 1: Create Prod Environment Directory

```bash
cp -r terraform/environments/dev terraform/environments/prod
```

Edit `terraform/environments/prod/terraform.tfvars`:
```hcl
environment     = "prod"
instance_type   = "t3.small"        # right-size based on load testing
instance_count  = 2                  # minimum 2 for HA
vpc_cidr        = "10.1.0.0/16"     # non-overlapping with dev
availability_zone = "eu-west-1a"    # expand to multi-AZ (see below)
```

Edit `terraform/environments/prod/backend.tf`:
```hcl
key = "prod/terraform.tfstate"      # separate state file
```

### Step 2: Multi-AZ for Production

Convert networking module to support multiple AZs:
- Change `availability_zone` (string) to `availability_zones` (list)
- Add subnets in `eu-west-1b` and `eu-west-1c`
- Add a second NAT Gateway for AZ redundancy (or accept single-NAT risk with documented RTO)
- ALB already accepts `public_subnet_ids` as a list — just pass all three

### Step 3: HTTPS

- Create an ACM certificate for the production domain
- Add an HTTPS listener (port 443) to the ALB with the ACM cert
- Redirect the HTTP listener (port 80) to HTTPS
- Update Nginx config to trust the `X-Forwarded-Proto` header from the ALB

### Step 4: Credential Separation

| Environment | AWS Account | OIDC Role | GitHub Environment |
|-------------|-------------|-----------|-------------------|
| dev | `111111111111` | `arn:aws:iam::111111111111:role/github-deploy-dev` | `dev` |
| prod | `222222222222` | `arn:aws:iam::222222222222:role/github-deploy-prod` | `prod` (with required reviewers) |

- **Separate AWS accounts** per environment (AWS Organizations) — strongest isolation
- **Separate OIDC roles** scoped to their respective accounts
- **GitHub Environment protection rules** on `prod`:
  - Required reviewers (manual approval gate)
  - Deployment branch restriction (only `main`)
  - Wait timer (optional cooldown)

### Step 5: Deploy Workflow Changes

Add a `prod` job to `deploy.yml` that:
1. Depends on the `dev` jobs completing successfully
2. References the `prod` GitHub Environment (triggers approval gate)
3. Uses the `prod` OIDC role ARN
4. Targets `terraform/environments/prod/`
5. Passes `environment=prod` to Ansible

### Step 6: Observability for Prod

- Set log retention to 30-90 days (compliance)
- Wire alarm actions to an SNS topic → PagerDuty/Slack
- Enable Secrets Manager automatic rotation with a Lambda function
- Increase ALB deregistration delay to 300s (allow in-flight request draining)
- Consider enabling VPC Flow Logs for ALL traffic (not just REJECT)

---

## Stretch Goals Implemented

| Stretch Goal | Status | Implementation |
|---|---|---|
| Manual approval before prod apply | Done (documented) | GitHub Environment protection rules with required reviewers |
| Avoid overlapping runs per environment | Done | `concurrency` groups with `cancel-in-progress: false` on deploy |
| Both observability paths | Done | Centralized logs (mandatory) + metrics/alarms (stretch) |
| Security scanning in CI | Done | tfsec + checkov |

---

## AWS Well-Architected Framework Alignment

### Security Pillar
- IMDSv2 enforced on all instances
- No port 22 open, SSM for management access
- Private subnets for EC2, no public IPs
- IAM least-privilege (instance profile scoped to specific Secrets Manager ARN)
- Encrypted EBS volumes (gp3)
- VPC Flow Logs for network auditing
- CIS-aligned OS hardening (sysctl, auditd, SSH)
- Systemd sandboxing (ProtectSystem, PrivateTmp, NoNewPrivileges)
- Security headers in Nginx (XSS, clickjacking, content-type sniffing)
- `drop_invalid_header_fields` on ALB (HTTP request smuggling prevention)

### Reliability Pillar
- Gunicorn restart-on-failure with rate limiting
- ALB health checks with configurable thresholds
- CloudWatch alarms on HealthyHostCount (all-targets-down detection)
- Dynamic inventory handles instance replacement
- Ansible idempotency ensures convergence after drift

### Operational Excellence Pillar
- Terraform modules with clear inputs/outputs
- Consistent tagging for cost/ownership tracking
- CI/CD pipeline for safe, visible rollouts
- Centralized logging for incident investigation
- Changelog documenting every infrastructure change

### Cost Optimization Pillar
- t3.micro (free tier eligible) for dev
- Single AZ to avoid duplicate NAT Gateway
- PAY_PER_REQUEST DynamoDB for state locking
- 7-day log retention in dev (vs 30-90 in prod)
- Cleanup instructions documented

### Performance Efficiency Pillar
- Gunicorn worker count tuned to instance CPU
- Nginx connection buffering protects app workers
- Nginx keepalive to upstream reduces connection overhead
- CloudWatch Agent custom metrics for capacity planning
