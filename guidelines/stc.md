# Prompt — Build the Project Foxtrot DevOps infrastructure from scratch

## Goal

Build a production-grade DevOps infrastructure for a minimal full-stack Todo application deployed on AWS EKS. The application is intentionally trivial (React + Express + PostgreSQL CRUD). The focus is infrastructure, CI/CD with GitOps, secrets management, observability, network security, and VPN-based operator access.

**Live at:** `https://todo.alexanderkachar.com`
**Repository:** `https://github.com/alexkachar/eks-pipeline-project-foxtrot`

---

## Repository structure

```
.github/workflows/ci.yml
app/
  backend/                    # Express API + Dockerfile
  frontend/                   # React + Vite + Dockerfile (Nginx)
k8s/helm/todo-app/            # Helm chart for the application
  image-overrides.yaml        # Image tags only — updated by CI, watched by ArgoCD
terraform/
  modules/vpc/
  modules/eks/
  modules/rds/
  modules/ecr/
  modules/route53/
  modules/runner/              # EC2 GitHub Actions runner
  modules/vpn/                 # WireGuard instance
  environments/dev/            # main.tf, helm.tf, providers.tf, variables.tf, outputs.tf, terraform.tfvars, backend.tf
guidelines/                    # project documentation
destroy.sh                     # pre-destroy script (see Operational section)
docker-compose.yml             # local dev only
```

---

## Application

### Backend — `app/backend/`
- Node.js + Express
- REST endpoints: `GET/POST /api/todos`, `PUT/DELETE /api/todos/:id`, `GET /api/health`, `GET /metrics`
- PostgreSQL via `pg` library; connection from env vars `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`
- SSL: `{ rejectUnauthorized: false }` by default; disabled when `DB_SSL=false` (local dev)
- Prometheus metrics via `prom-client`: `http_requests_total`, `http_request_duration_seconds`, `db_query_duration_seconds`
- Dockerfile: multi-stage, non-root user, port 3000
- `init.sql`: creates the `todos` table

### Frontend — `app/frontend/`
- React + Vite; simple CRUD UI
- API calls to `/api/*` (relative — routed by ALB in K8s, proxied by Nginx locally)
- Dockerfile: multi-stage (Vite build → Nginx alpine), port 80
- `nginx.conf` (production): serves static files, SPA fallback, no `/api` proxy (ALB handles routing)
- `nginx.local.conf`: same but with `proxy_pass http://backend:3000` for `/api/` — mounted via docker-compose

### docker-compose.yml (local dev only)
- Services: `postgres` (postgres:16-alpine), `backend` (port 3000), `frontend` (port 80)
- Backend env includes `DB_SSL: "false"`
- Frontend mounts `./app/frontend/nginx.local.conf` over `/etc/nginx/conf.d/default.conf`

---

## AWS infrastructure

### Variables / account-specific
- Region: `us-east-1`
- Domain: `alexanderkachar.com` — ACM wildcard cert and Route 53 hosted zone must already exist
- EKS version: `1.35`
- Node type: `t3.large` × 2, `AL2023_x86_64_STANDARD`, private subnets only
- RDS: `db.t4g.micro`, PostgreSQL (latest engine), `gp3`, encrypted, `skip_final_snapshot = true`, `deletion_protection = false`
- Terraform state: S3 bucket + DynamoDB table for locking (must exist before first apply)

### VPC module
- CIDR `10.0.0.0/16`, 6 subnets across 2 AZs: 2 public (ALB, VPN), 2 private (EKS nodes, EC2 runner), 2 database (RDS)
- Public subnets tagged `kubernetes.io/role/elb = 1`
- Private subnets tagged `kubernetes.io/role/internal-elb = 1`
- Internet Gateway on public subnets
- **NAT Gateway** — single, in AZ-0. Private route table routes `0.0.0.0/0` through it.
- **VPC Endpoints** (all with `private_dns_enabled = true`; security group allows HTTPS/443 from VPC CIDR): `ecr.api`, `ecr.dkr`, `s3` (Gateway), `eks`, `ec2`, `sts`, `ssm`, `ssmmessages`, `ec2messages`, `logs`
- RDS subnet group covering database subnets

### ECR module
- Repositories: `todo-app-frontend`, `todo-app-backend`
- `force_delete = true`
- Lifecycle policy: keep last 10 images

### RDS module
- Instance in database subnets
- Security group: inbound 5432 only from private subnet CIDRs
- Credentials generated via `random_password`, stored in SSM Parameter Store as SecureString:
  - `/todo-app/dev/db-host`, `db-port`, `db-name`, `db-user`, `db-password`

### EKS module
- **Fully private API endpoint** — no public access. All cluster management goes through VPN.
- Control plane logging: `api`, `audit`, `authenticator`
- OIDC provider for IRSA
- Node IAM role: `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonSSMManagedInstanceCore`
- **IRSA roles** (reusable trust policy via `for_each`):
  - `alb_controller` → official ALB Controller IAM policy JSON (from file)
  - `eso` → `ssm:GetParameter*` on `/todo-app/*`

### EC2 runner module
- **Purpose:** self-hosted GitHub Actions runner for CI only (image builds). No cluster access.
- Instance: `t3.medium` in a private subnet
- Software installed via user data: GitHub Actions runner agent, Docker, `amazon-ecr-credential-helper`
- **No AWS CLI, no kubectl, no Helm** on this instance
- IAM instance profile scoped to ECR push only: `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:BatchGetImage`
- Runner registration: user data reads GitHub PAT from SSM (`var.runner_github_token_parameter_name`), registers the runner against the repo
- Security group: **egress only** (HTTPS outbound for GitHub polling, Docker pulls via NAT, ECR via VPC endpoint). No inbound rules.
- The GitHub PAT needs `repo` scope (for runner registration) and `contents: write` (for pushing image tag commits)

### VPN module
- **Purpose:** operator access to private EKS endpoint and internal ALB (monitoring)
- WireGuard on `t3.micro` (or `t4g.micro`) in a public subnet
- Security group: inbound UDP on WireGuard port (e.g. 51820) from `var.developer_ip_cidr`, outbound all to VPC CIDR
- User data generates server keys and WireGuard config on boot
- Client config (public key, endpoint, allowed IPs) exposed via Terraform output or SSM parameter for easy retrieval
- Routes VPN clients into the VPC — enables browser access to internal ALB and kubectl access to private EKS endpoint

### Route 53 module
- A alias record: `todo.alexanderkachar.com` → public ALB (internet-facing, for the todo-app)
- **Conditional:** `count = var.alb_dns_name != "" ? 1 : 0`. Leave empty on first apply; fill after ALB provisions.

### Terraform providers
- Use `exec`-based EKS auth for Helm, Kubernetes, and kubectl providers (not token-based — tokens expire in 15 min and long applies fail)
- S3 backend with DynamoDB locking in `backend.tf`

---

## Cluster addons — `terraform/environments/dev/helm.tf`

All installed via Terraform's Helm provider.

| Addon | Chart | Namespace | Notes |
|---|---|---|---|
| AWS Load Balancer Controller | `aws-load-balancer-controller` (eks charts) | `kube-system` | IRSA annotated SA |
| External Secrets Operator | `external-secrets` (external-secrets repo) | `external-secrets` | IRSA annotated SA; create `ClusterSecretStore` pointing to SSM in `us-east-1` |
| ArgoCD | `argo-cd` (argoproj repo) | `argocd` | Manages todo-app only. Access via VPN. |
| kube-prometheus-stack | prometheus-community | `monitoring` | `grafana.persistence.enabled=false`, `prometheus.retention=6h`, Loki datasource configured in values |
| Loki | `loki` (grafana repo) | `monitoring` | Single-binary mode, filesystem storage, no S3 backend |
| Promtail | `promtail` (grafana repo) | `monitoring` | DaemonSet, ships logs to Loki |

---

## Helm chart — `k8s/helm/todo-app/`

### Values structure
- `values.yaml` — all defaults: replica counts, service ports, resource limits, image repositories (without tags)
- `image-overrides.yaml` — image tags only, updated by CI pipeline. Kept separate to avoid triggering CI on tag-bump commits.

### Templates
- `backend-deployment.yaml` — 2 replicas, ECR image, env from K8s secret `todo-app-db-credentials`, readiness probe on `/api/health`, rolling update (`maxSurge: 1`, `maxUnavailable: 0`)
- `backend-service.yaml` — ClusterIP, port 3000
- `frontend-deployment.yaml` — 2 replicas, Nginx image
- `frontend-service.yaml` — ClusterIP, port 80
- `ingress.yaml` — **Public ALB**: `internet-facing`, `target-type: ip`, ACM cert ARN, `listen-ports: HTTP:80 + HTTPS:443`, `ssl-redirect: 443`, path rules (`/api/*` → backend, `/*` → frontend)
- `monitoring-ingress.yaml` — **Internal ALB**: `scheme: internal`, routes to Grafana service in `monitoring` namespace. Accessible only through VPN.
- `externalsecret.yaml` — references `ClusterSecretStore: aws-ssm`, pulls `/todo-app/dev/db-*` into K8s secret `todo-app-db-credentials`
- `servicemonitor.yaml` — Prometheus scrapes `/metrics` on backend every 30s; label `release: kube-prometheus-stack`
- `prometheusrule.yaml` — basic alerts: high error rate (>5% 5xx over 5 min), pod restart loops (>3 restarts in 15 min), RDS connection failures
- `grafana-dashboard.yaml` — ConfigMap with `grafana_dashboard: "1"` label; auto-loaded by Grafana sidecar. Include panels for request rate, latency percentiles, error rate, and a log panel from Loki.

---

## CI/CD pipeline

### CI — `.github/workflows/ci.yml`
- Trigger: push to `main`, paths:
  - `app/**`
  - `k8s/helm/todo-app/**`
  - `!k8s/helm/todo-app/image-overrides.yaml`
  - `.github/workflows/ci.yml`
- `runs-on: self-hosted` (runner registers against `alexkachar/eks-pipeline-project-foxtrot`)
- Steps:
  1. Checkout
  2. Configure Docker to use ECR credential helper
  3. `docker build` + `docker push` frontend → ECR (tags: `${{ github.sha }}` and `latest`)
  4. `docker build` + `docker push` backend → same pattern
  5. Update `k8s/helm/todo-app/image-overrides.yaml` with new tags
  6. `git commit` + `git push` the image-overrides change (use the runner's GitHub PAT)

No AWS CLI needed — ECR credential helper handles authentication via the instance profile.

### CD — ArgoCD
- ArgoCD Application CR (deployed by Terraform or manually on first bootstrap):
  - Source: Git repo, path `k8s/helm/todo-app/`
  - Helm values files: `values.yaml` + `image-overrides.yaml`
  - Destination: `todo-app` namespace
  - Sync policy: automated, with self-heal and prune enabled
- When CI pushes updated image tags to Git, ArgoCD detects the change and syncs automatically.

---

## Observability

All monitoring behind the internal ALB — accessible only through VPN.

- **Prometheus**: scrapes backend `/metrics` via ServiceMonitor + all default kube-prometheus-stack targets. 6h retention.
- **Loki**: single-binary mode, filesystem storage. Promtail DaemonSet collects logs from all pods.
- **Grafana**: no persistence (ephemeral environment). Datasources (Prometheus + Loki) configured in kube-prometheus-stack Helm values. Dashboards delivered as ConfigMaps.
- **Alerting**: PrometheusRule CRs for basic alerts. Visible in Grafana alerting tab — no external notification channel needed.

---

## Operational

### Destroy
The public ALB and internal ALB are created by the ALB Controller (from Ingress resources) and are **not in Terraform state**. Direct `terraform destroy` will fail trying to delete the VPC while ALBs still exist.

`destroy.sh` handles this: uninstalls `todo-app` Helm release → deletes monitoring ingress → polls until both ALBs are gone → clears `alb_dns_name` in tfvars → runs `terraform destroy`.

### Bootstrap sequence
1. `terraform apply` — provisions VPC, EKS, RDS, ECR, runner, VPN, and all cluster addons including ArgoCD
2. Connect to VPN, run `aws eks update-kubeconfig --name <cluster-name> --region us-east-1`
3. Deploy todo-app via ArgoCD (create Application CR) or one-time `helm install`
4. Wait ~2 min for ALB, capture its DNS: `kubectl get ingress -n todo-app -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'`
5. Update `alb_dns_name` in `terraform.tfvars`, run `terraform apply` again for Route 53 record
6. All subsequent deploys are automatic via CI → ArgoCD

---

## Prerequisites (must exist before `terraform apply`)

- ACM wildcard certificate for `*.alexanderkachar.com` in `us-east-1`
- Route 53 hosted zone for `alexanderkachar.com`
- GitHub PAT in SSM at the path set in `runner_github_token_parameter_name` (needs `repo` + `contents:write` scope)
- S3 bucket and DynamoDB table for Terraform state
- GitHub repository: `https://github.com/alexkachar/eks-pipeline-project-foxtrot`

---

## Repository documentation

### README.md
Generate a `README.md` at the repository root. It should cover:
- Project overview (what this is, what the focus is)
- Architecture diagram (text-based, e.g. Mermaid or ASCII — showing VPC layout, CI/CD flow, and observability stack)
- Prerequisites (what must exist before deploying)
- Bootstrap sequence (how to bring the environment up)
- Teardown instructions (how to destroy cleanly)
- Repository structure (brief description of each top-level directory)
- CI/CD flow summary (push → build → image-overrides commit → ArgoCD sync)

Keep it concise — a reader should understand the project's scope and how to run it within 2 minutes of reading.

### .gitignore
Generate a `.gitignore` appropriate for a public repo containing Terraform, Node.js, and Docker. Must include at minimum:
- Terraform: `.terraform/`, `*.tfstate`, `*.tfstate.*`, `*.tfvars` (contains sensitive values), `.terraform.lock.hcl`
- Node.js: `node_modules/`, `dist/`, `.env`
- OS files: `.DS_Store`, `Thumbs.db`
- IDE: `.vscode/`, `.idea/`
- Docker: no ignores needed, but ensure no `.env` files are committed
- WireGuard client configs (if generated locally)

**Important:** `terraform.tfvars` must be gitignored — it contains the developer IP, ALB DNS name, and references to SSM parameter paths. Provide a `terraform.tfvars.example` with placeholder values instead.
