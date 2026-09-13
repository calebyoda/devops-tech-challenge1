# Tech Challenge 1 / Project 4 — DevOps CI/CD Pipeline on AWS ECS

A Node.js frontend and backend deployed to AWS ECS Fargate, provisioned entirely with Terraform, with a Jenkins CI/CD pipeline automating builds and deployments on every push to `main`. Includes a required GitOps alternative using GitHub Actions.

## Architecture

- **Frontend**: React app (Create React App), served via `serve` in a Docker container
- **Backend**: Express API, generates a UUID on request
- **Infrastructure**: VPC with public/private subnets, NAT Gateway, Application Load Balancer, ECS Fargate cluster, ECR repositories, IAM roles, CloudWatch logging, target-tracking autoscaling
- **CI/CD**: Jenkins running on an EC2 instance, triggered by a GitHub webhook, building Docker images and deploying to ECS
- **Region**: `us-east-1`

## Prerequisites

- Docker Desktop
- AWS CLI, configured with credentials that have access to create the resources below
- Terraform v1.15+
- Node.js (use `nvm` to switch to **Node 16** — this project's dependencies are incompatible with newer Node versions; see Known Issues below)
- Git, with SSH access configured for GitHub

## Local Setup (Phases 1–2)

1. Clone the repo and `cd` into it.
2. Backend: `cd backend && npm ci && npm start` — runs on `localhost:8080`.
3. Frontend: in a new terminal, `cd frontend`, confirm `src/config.js` points at your backend, `npm ci && npm start` — runs on `localhost:3000`.
4. Confirm the frontend displays a GUID matching the backend's raw JSON response.
5. Docker: each service has a `Dockerfile`. Build with `docker build -t <name> .`, run with `docker run -d -p <port>:<port> <name>`.

## Infrastructure (Phase 3)

All AWS infrastructure is defined in `/terraform`. To provision:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

This creates 44+ resources: VPC/networking, security groups, IAM roles, ECR repositories, ECS cluster/services/task definitions, an Application Load Balancer, autoscaling policies, and the Jenkins EC2 instance. Outputs (ALB DNS name, ECR URLs, Jenkins URL, etc.) print automatically on completion, or retrieve any of them later with `terraform output <name>`.

**Note:** the Jenkins EC2 instance's `key_name` in `jenkins.tf` must reference an EC2 key pair that already exists in your AWS account, in the same region as your deployment (`us-east-1`). If you don't already have one, create it before running `terraform apply`: **AWS Console → EC2 → Key Pairs → Create key pair**. Download and securely store the resulting `.pem` file — AWS only lets you download it once, and you'll need it to SSH into the Jenkins instance in the next step. Update `key_name` in `jenkins.tf` to match whatever name you give it.

## Jenkins Setup (Phase 4)

1. SSH into the Jenkins instance: `ssh -i <your-key>.pem ec2-user@<jenkins_master_public_ip>`
2. Install Docker on the host, then run Jenkins as a container:
```bash
   docker run -d --name jenkins -p 8080:8080 \
     -v /var/jenkins_home:/var/jenkins_home \
     -v /var/run/docker.sock:/var/run/docker.sock \
     --group-add <docker_group_gid> \
     jenkins/jenkins:lts
```
3. Ensure `/var/jenkins_home` is owned by UID/GID 1000 on the host **before** starting the container (`sudo chown -R 1000:1000 /var/jenkins_home`) — Jenkins runs as a non-root user and cannot write to a root-owned mount.
4. Retrieve the initial admin password: `docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword`
5. Complete setup at `http://<jenkins_master_public_ip>:8080`, installing suggested plugins plus **Docker**, **Amazon EC2**, and **Amazon ECS/Fargate**.
6. Install the Docker CLI and AWS CLI **inside** the Jenkins container itself (`docker exec -u root -it jenkins bash`, then install both) — the pipeline calls both directly and neither ships with the base Jenkins image. **Note:** this install does not persist if the container is ever recreated; only `/var/jenkins_home` persists.
7. Add two credentials in Jenkins (Manage Jenkins → Credentials): an **AWS Credentials** entry for a scoped IAM user (ECR push/pull + ECS update, limited to this project's specific resources), and a **Username with password** entry using a GitHub PAT.

## CI/CD Pipeline (Phase 5)

The `Jenkinsfile` at the repo root defines five stages: checkout, build Docker images, authenticate to ECR, tag and push images, and update ECS services (`--force-new-deployment`).

Pipeline job configuration: "Pipeline script from SCM," pointed at this repo's `main` branch, with the GitHub webhook trigger enabled (`http://<jenkins_public_ip>:8080/github-webhook/` configured on the GitHub repo side). Every push to `main` automatically rebuilds and redeploys both services.

## Live Deployment (Phase 6)

- **Frontend URL**: `http://<your-alb-dns-name>`
- Frontend and backend `config.js` files must point at the ALB's DNS name (not `localhost`), with the frontend's API URL including a **trailing slash** (`/api/`) to match the ALB's `/api/*` listener rule.

## Load Testing & Autoscaling (Phase 7)

Load tested using Siege in benchmark mode via Docker (no native install required):
```bash
docker run --rm jstarcher/siege siege -b -c 150 -t 5m http://<your-alb-dns-name>
```

**Result:** frontend service scaled from 1 → 2 → 4 tasks (the configured `max_tasks` ceiling) under sustained CPU load, confirmed via `aws ecs describe-services` and CloudWatch metrics.

**Finding worth noting:** an initial test using Siege's default mode (with built-in delays between requests) produced oscillating CPU spikes that never sustained long enough to trigger the autoscaling alarm's required 3 consecutive breaching minutes. Diagnosed by cross-referencing `aws cloudwatch get-metric-statistics` (confirmed real CPU spikes occurred) against `aws application-autoscaling describe-scaling-activities` (confirmed zero scaling attempts were made) — ruling out a policy or permissions failure before identifying the actual cause (Siege's default per-request delay). Resolved with the `-b` benchmark flag.

Scale-in (back down to 1 task) takes substantially longer than scale-out, by design — the low-CPU alarm requires 15 consecutive minutes below threshold, versus 3 minutes for the high-CPU alarm, avoiding premature capacity removal after a brief lull. Confirmed the full cycle: after the Siege test ended, the frontend service scaled back down from 4 tasks to the baseline of 1 once CPU had remained low long enough for the low-CPU alarm to trigger.

## Known Issues & Resolutions

| Issue | Cause | Fix |
|---|---|---|
| `ERR_PACKAGE_PATH_NOT_EXPORTED` on frontend build (local and in Docker) | Node 24 (and Node 18 in the frontend Dockerfile) enforce strict `package.json` `exports` resolution incompatible with this project's older `postcss` dependency | Pinned to Node 16 both locally (via `nvm`) and in the frontend `Dockerfile` |
| `terraform apply` failed creating the backend ECS service: target group had no associated load balancer | Missing `aws_lb_listener_rule` resource for the backend in `alb.tf` — an incomplete reference in the original walkthrough | Added the listener rule; also added explicit `depends_on` on the backend ECS service |
| Jenkins container exited immediately after first run | `/var/jenkins_home` on the EC2 host was owned by `root`; Jenkins runs internally as UID 1000 | `chown -R 1000:1000` on the host mount before restarting the container |
| Pipeline failed at "Build Docker images": `docker: not found` | Docker CLI not installed inside the Jenkins container (only the host has it) | Installed Docker CLI inside the container via `apt-get install docker.io` |
| Deployed app showed `NetworkError` | Frontend's compiled JS still pointed at `localhost:8080` (`REACT_APP_*` env vars only apply at build time, not runtime) | Updated `config.js` to the ALB's DNS name and rebuilt |
| Deployed app showed `JSON.parse: unexpected character` | `config.js` exported an object where `App.js` expected a plain URL string, producing a literal `/[object Object]` request path | Changed `config.js` to export a plain string |
| Same error persisted after the above fix | Missing trailing slash — ALB rule matches `/api/*`, request was going to exactly `/api` | Added trailing slash: `/api/` |

## GitOps Alternative (Phase 9)

*(to be completed)*

## Submission

- GitHub repo: `https://github.com/calebyoda/devops-tech-challenge1` (private, shared with reviewer)
- Jenkins URL and credentials: provided separately in the submission form, not committed here
- Frontend public URL: provided in the submission form