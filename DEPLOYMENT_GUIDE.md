# Hospital Management System — Full DevOps Deployment Guide

Prerequisites before you start:
- AWS account with an IAM user that has admin (or near-admin) permissions for a learning project
- AWS CLI installed and configured (`aws configure`)
- Docker installed and running
- Terraform installed (v1.5+)
- `kubectl` installed
- Git + GitHub account
- `helm` installed (for Prometheus/Grafana later)

Work through the steps **in order**. Do not skip to Terraform before Docker works locally — each phase assumes the previous one is verified working.

---

## Step 1 — Prepare the GitHub repository

```bash
git clone https://github.com/<your-username>/Hospital-Management-System.git
cd Hospital-Management-System
```

Reorganize into this structure:

```
Hospital-Management-System/
├── application/            # your existing html/css/js goes here
├── docker/
├── kubernetes/
├── terraform/
├── scripts/
├── .github/workflows/
└── README.md
```

Move your existing `.html` files and `assets/` folder into `application/`.

```bash
mkdir -p application docker kubernetes terraform scripts .github/workflows
git mv index.html about.html doctors.html appointment.html contact.html \
       gallery.html blog.html login.html registration.html privacy.html terms.html \
       application/ 2>/dev/null
git mv assets application/ 2>/dev/null
git add -A
git commit -m "Reorganize repo structure for DevOps pipeline"
git push
```

**Checkpoint:** `application/index.html` exists and opens fine as a static file in your browser.

---

## Step 2 — Dockerize the application

Create `docker/nginx.conf`:

```nginx
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /healthz {
        access_log off;
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }
}
```

Create `docker/Dockerfile` (multi-stage, even though the app is static — this is intentional so you learn the pattern):

```dockerfile
# ---- Stage 1: prepare static assets ----
FROM alpine:3.20 AS builder

WORKDIR /app
COPY application/ .

# Placeholder for a real build step later (minify, bundle, etc.)
RUN echo "Build stage complete" > /app/build.log

# ---- Stage 2: serve with nginx ----
FROM nginx:1.27-alpine AS production

COPY --from=builder /app /usr/share/nginx/html
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

Create `docker/.dockerignore`:

```
.git
.github
terraform
kubernetes
scripts
README.md
*.md
```

**Checkpoint:** files exist at `docker/Dockerfile`, `docker/nginx.conf`, `docker/.dockerignore`.

---

## Step 3 — Build and test locally

Run from the repo root (note the `-f` flag since the Dockerfile isn't at root):

```bash
docker build -f docker/Dockerfile -t hospital-management:v1 .
docker run -d --name hospital-app -p 8080:80 hospital-management:v1
docker ps
curl http://localhost:8080/healthz
```

Open `http://localhost:8080` in a browser and click through Home, Doctors, Appointments, Login.

Common failure here: **"COPY failed: file not found"** — this means your build context is wrong. You must run `docker build` from the repo root (where `application/` lives), not from inside `docker/`.

Clean up before moving on:

```bash
docker rm -f hospital-app
```

**Checkpoint:** the site loads at localhost:8080 and `/healthz` returns `ok`.

---

## Step 4 — Terraform: providers and versions

Create `terraform/versions.tf`:

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}
```

Create `terraform/providers.tf`:

```hcl
provider "aws" {
  region = var.aws_region
}
```

Create `terraform/variables.tf`:

```hcl
variable "aws_region" {
  default = "us-east-1"
}

variable "project_name" {
  default = "hospital-management"
}

variable "cluster_name" {
  default = "hospital-eks"
}
```

Create `terraform/outputs.tf` (empty for now, we'll add outputs per resource file):

```hcl
# outputs added incrementally in vpc.tf, eks.tf, ecr.tf
```

```bash
cd terraform
terraform init
```

**Checkpoint:** `terraform init` succeeds with no errors, and a `.terraform/` folder + `.terraform.lock.hcl` appear.

---

## Step 5 — Terraform: ECR

Create `terraform/ecr.tf`:

```hcl
resource "aws_ecr_repository" "hospital" {
  name                 = var.project_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

output "ecr_repository_url" {
  value = aws_ecr_repository.hospital.repository_url
}
```

```bash
terraform plan
terraform apply
```

Push your first image:

```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

docker tag hospital-management:v1 <account-id>.dkr.ecr.us-east-1.amazonaws.com/hospital-management:v1
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/hospital-management:v1
```

Common failure: **"no basic auth credentials"** — your ECR login expired (tokens last 12 hours) or region mismatch. Re-run the `get-login-password` command.

**Checkpoint:** `terraform apply` created the ECR repo, and the image shows up when you run `aws ecr list-images --repository-name hospital-management`.

---

## Step 6 — Terraform: VPC

Create `terraform/vpc.tf`. Use the official module rather than hand-rolling this — it's the standard approach and avoids subnet/routing mistakes:

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true   # cost-saving for a learning project; use false for real HA
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/${var.cluster_name}"  = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/${var.cluster_name}"  = "shared"
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "public_subnets" {
  value = module.vpc.public_subnets
}
```

```bash
terraform init   # re-init to pull the new module
terraform plan
terraform apply
```

Common failure: **"InvalidParameterException: at least one subnet is required per AZ"** — this happens if you set `azs` to fewer than 3 zones but reference 3 CIDR blocks. Keep the counts matched (3 AZs, 3 private, 3 public).

**Checkpoint:** `terraform apply` completes; `aws ec2 describe-vpcs` shows the new VPC with 6 subnets total.

---

## Step 7 — Terraform: EKS

Create `terraform/eks.tf`:

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.30"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    default = {
      min_size       = 3
      max_size       = 6
      desired_size   = 3
      instance_types = ["t3.medium"]
    }
  }
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}
```

```bash
terraform init
terraform plan
terraform apply
```

This step takes 12–18 minutes — EKS control plane provisioning is slow. Don't panic if it looks stuck.

Common failures:
- **"UnauthorizedOperation"** — your IAM user/role lacks EKS or EC2 permissions. Attach `AmazonEKSClusterPolicy`-equivalent admin rights for now.
- **"Error: waiting for EKS Node Group... NodeCreationFailure"** — usually means your private subnets don't have NAT gateway routing to reach the EKS API/ECR. Verify `enable_nat_gateway = true` in Step 6 actually applied.
- **Apply hangs then times out** — check you're not hitting your account's EIP or VPC limits (`aws ec2 describe-account-attributes`).

**Checkpoint:** `aws eks describe-cluster --name hospital-eks` returns `"status": "ACTIVE"`.

---

## Step 8 — Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name hospital-eks
kubectl get nodes
```

You should see 3 nodes in `Ready` state.

Common failure: **"error: You must be logged in to the server (Unauthorized)"** — the IAM identity running `kubectl` isn't mapped into the cluster's `aws-auth` ConfigMap. If you created the cluster with a different IAM user/role than the one you're using now, you need to add it via `aws_auth` in the eks module or edit the ConfigMap directly.

**Checkpoint:** `kubectl get nodes` shows 3 nodes Ready.

---

## Step 9 — Kubernetes: namespace, deployment, service

Create `kubernetes/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: hospital
```

Create `kubernetes/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hospital-deployment
  namespace: hospital
  labels:
    app: hospital
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hospital
  template:
    metadata:
      labels:
        app: hospital
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values: ["hospital"]
                topologyKey: "kubernetes.io/hostname"
      containers:
        - name: hospital
          image: <account-id>.dkr.ecr.us-east-1.amazonaws.com/hospital-management:v1
          ports:
            - containerPort: 80
          readinessProbe:
            httpGet:
              path: /healthz
              port: 80
            initialDelaySeconds: 3
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /healthz
              port: 80
            initialDelaySeconds: 10
            periodSeconds: 10
          resources:
            requests:
              cpu: "100m"
              memory: "64Mi"
            limits:
              cpu: "250m"
              memory: "128Mi"
```

Create `kubernetes/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: hospital-service
  namespace: hospital
spec:
  type: ClusterIP
  selector:
    app: hospital
  ports:
    - port: 80
      targetPort: 80
```

Apply:

```bash
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml

kubectl get pods -n hospital
kubectl get svc -n hospital
```

Common failure: **`ImagePullBackOff`** — almost always one of:
1. The image tag in `deployment.yaml` doesn't match what you actually pushed to ECR (check `<account-id>` and tag)
2. The node group's IAM role doesn't have `AmazonEC2ContainerRegistryReadOnly` attached (the EKS module usually adds this automatically — verify in IAM console if it fails)

**Checkpoint:** `kubectl get pods -n hospital` shows 3 pods `Running` with `1/1 Ready`.

---

## Step 10 — Verify 3 replicas and self-healing

```bash
kubectl get pods -n hospital -o wide
```

Confirm the 3 pods are spread across different nodes (different AZs). Test self-healing:

```bash
kubectl delete pod <one-pod-name> -n hospital
kubectl get pods -n hospital -w
```

Watch Kubernetes create a replacement pod automatically.

**Checkpoint:** deleted pod is replaced within seconds; you're always at 3/3 Running.

---

## Step 11 — ALB Ingress

You need the **AWS Load Balancer Controller** installed via Helm before Ingress objects will create real ALBs.

```bash
# 1. Create IAM policy + service account (one-time setup)
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.9.0/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

eksctl utils associate-iam-oidc-provider --cluster hospital-eks --approve

eksctl create iamserviceaccount \
  --cluster=hospital-eks \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::<account-id>:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

# 2. Install the controller
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=hospital-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

Create `kubernetes/ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hospital-ingress
  namespace: hospital
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: hospital-service
                port:
                  number: 80
```

```bash
kubectl apply -f kubernetes/ingress.yaml
kubectl get ingress -n hospital
```

Wait 2–3 minutes, then check the `ADDRESS` column for the ALB DNS name.

Common failure: **Ingress has no ADDRESS after 5+ minutes** — check controller logs:
```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```
Usually it's a subnet tagging issue (Step 6's `kubernetes.io/role/elb` tags) or the IAM policy wasn't attached correctly.

**Checkpoint:** the ALB DNS name in `kubectl get ingress -n hospital` loads your site in a browser.

---

## Step 12 — Health checks (already embedded above)

You already added `readinessProbe`/`livenessProbe` in Step 9's `deployment.yaml`, and `healthcheck-path` in Step 11's Ingress annotation. Verify:

```bash
kubectl describe pod -n hospital <pod-name> | grep -A3 "Liveness\|Readiness"
```

**Checkpoint:** both probes show as configured and passing (no `Warning Unhealthy` events in `kubectl describe`).

---

## Step 13 — HPA + PodDisruptionBudget

You need the **metrics-server** installed for HPA to work:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl get deployment metrics-server -n kube-system
```

Create `kubernetes/hpa.yaml`:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: hospital-hpa
  namespace: hospital
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: hospital-deployment
  minReplicas: 3
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

Create `kubernetes/pdb.yaml`:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: hospital-pdb
  namespace: hospital
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: hospital
```

```bash
kubectl apply -f kubernetes/hpa.yaml
kubectl apply -f kubernetes/pdb.yaml
kubectl get hpa -n hospital
```

Common failure: **HPA shows `<unknown>/70%` for TARGETS** — metrics-server isn't ready yet, or (on EKS specifically) it needs `--kubelet-insecure-tls` in some setups. Wait 1-2 minutes first; if it persists, patch the metrics-server deployment args.

**Checkpoint:** `kubectl get hpa -n hospital` shows a real CPU percentage, not `<unknown>`.

---

## Step 14 — CI/CD with GitHub Actions

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Lint HTML
        run: |
          npx html-validate application/*.html || true

      - name: Build Docker image
        run: docker build -f docker/Dockerfile -t hospital-management:ci .

      - name: Smoke test container
        run: |
          docker run -d --name test-app -p 8080:80 hospital-management:ci
          sleep 3
          curl -f http://localhost:8080/healthz
          docker rm -f test-app
```

Create `.github/workflows/cd.yml`:

```yaml
name: CD

on:
  push:
    tags:
      - "v*"

env:
  AWS_REGION: us-east-1
  ECR_REPOSITORY: hospital-management
  EKS_CLUSTER: hospital-eks

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<account-id>:role/github-actions-deploy
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to ECR
        id: ecr-login
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build, tag, push image
        env:
          REGISTRY: ${{ steps.ecr-login.outputs.registry }}
          TAG: ${{ github.ref_name }}
        run: |
          docker build -f docker/Dockerfile -t $REGISTRY/$ECR_REPOSITORY:$TAG .
          docker push $REGISTRY/$ECR_REPOSITORY:$TAG

      - name: Update kubeconfig
        run: aws eks update-kubeconfig --name $EKS_CLUSTER --region $AWS_REGION

      - name: Deploy to EKS
        env:
          REGISTRY: ${{ steps.ecr-login.outputs.registry }}
          TAG: ${{ github.ref_name }}
        run: |
          kubectl set image deployment/hospital-deployment \
            hospital=$REGISTRY/$ECR_REPOSITORY:$TAG -n hospital
          kubectl rollout status deployment/hospital-deployment -n hospital
```

**Do not use long-lived AWS access keys in GitHub secrets.** Set up OIDC federation instead (an IAM role GitHub Actions can assume) — this is what `role-to-assume` above expects. This is a common trip-up, so if CD fails on the credentials step, that's almost certainly why.

Release a version:

```bash
git tag v1.0.0
git push origin v1.0.0
```

**Checkpoint:** the `cd.yml` workflow runs green in the GitHub Actions tab, and `kubectl rollout status` completes in the logs.

---

## Step 15 — Prometheus + Grafana

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

kubectl create namespace monitoring

helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring
```

This installs Prometheus, Grafana, and Alertmanager together (the `kube-prometheus-stack` chart bundles all three plus sensible defaults).

```bash
kubectl get pods -n monitoring
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

Open `http://localhost:3000` (default login `admin` / `prom-operator` unless you set your own).

**Checkpoint:** Grafana loads, and the default Kubernetes dashboards show your 3 nodes and hospital pods.

---

## Step 16 — Test failure scenarios (prove HA)

Run these and confirm the site stays up throughout:

```bash
# Kill a pod — should self-heal
kubectl delete pod -n hospital -l app=hospital --field-selector status.phase=Running -o name | head -1 | xargs kubectl delete

# Cordon a node and drain it — pods should reschedule elsewhere
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Load test to trigger HPA scale-up (needs a load tool, e.g. hey or k6)
hey -z 60s -c 50 http://<alb-dns-name>/
kubectl get hpa -n hospital -w
```

**Checkpoint:** ALB URL stays reachable during the pod kill and node drain; HPA scales replicas up under load and back down after.

---

## Step 17 — Document everything

Write a `README.md` covering: architecture diagram, how to run locally, how to deploy, how CI/CD works, and how to tear down. This is what you'll actually walk an interviewer through — keep it concrete and command-based, not just prose.

---

## Step 18 — Clean up AWS resources

**Important — EKS + ALB + NAT gateways cost money by the hour.** When you're done for the day:

```bash
kubectl delete ingress hospital-ingress -n hospital   # deletes the ALB first
helm uninstall prometheus -n monitoring
helm uninstall aws-load-balancer-controller -n kube-system

cd terraform
terraform destroy
```

Always delete the Ingress (and anything that provisioned an ALB/NLB) **before** `terraform destroy` — otherwise Terraform can't delete the VPC because AWS-created load balancer ENIs are still attached to it, and you'll get stuck with orphaned resources.

**Checkpoint:** `aws eks list-clusters` and `aws ec2 describe-vpcs` no longer show your resources.

---

## Debugging checklist (come back here when something fails)

| Symptom | Most likely cause |
|---|---|
| `docker build` can't find files | Wrong build context — run from repo root with `-f docker/Dockerfile` |
| `terraform apply` fails on IAM | Your AWS user lacks permissions for that resource type |
| EKS node group creation fails | NAT gateway/private subnet routing broken (Step 6) |
| `kubectl` unauthorized | IAM identity not in cluster's `aws-auth` mapping |
| `ImagePullBackOff` | Wrong image tag/account ID, or node IAM role missing ECR read policy |
| Ingress never gets an ADDRESS | LB Controller not installed, or subnets missing `kubernetes.io/role/elb` tags |
| HPA shows `<unknown>` | metrics-server not installed/ready yet |
| GitHub Actions CD fails on auth | Long-lived keys vs OIDC role mismatch |
| `terraform destroy` hangs on VPC | Orphaned ALB/NLB still attached — delete Ingress first |

When you hit an error, paste the **exact command you ran** and the **exact error text** and I'll pinpoint the fix.
