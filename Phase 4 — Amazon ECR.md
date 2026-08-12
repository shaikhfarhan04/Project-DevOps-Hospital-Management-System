Great. **Phase 4 — Amazon ECR** is next.

The goal is to take the Docker image you built locally and push it into **Amazon Elastic Container Registry (ECR)**.

![Image](https://images.openai.com/static-rsc-4/p-WjNbyNOfiQR4dZrGqNvMpwei5QEJlUHaX5wY3Ti4ByTnugb3q1V1dUroJ2-btRnVlRkm-bHLSfCvRzRvAx1hFKQ2_bQAs78PPtJph9VlXjXQ7IDjUGTxrqpCZlngLoHlwm5s3L48UuSI3Ga6iRgbr2yKAdbdR1PuOXXrEYMf3GZwNsWypuxFvuXdqPPslJ?purpose=fullsize)

![Image](https://images.openai.com/static-rsc-4/Ry8LYG9UKCynJaVmEdYan8CMZ8tJQFh8IHC_qaT7gVI-BcK8sdhXcuCSjE8MxwTW7m7svr_o6Bd0Of-Uhwk0mZkwbx1Zxktws364FIv7zOItC1c7p7K3kvIM4JE2xeq7fUOU2SRws8odI9Uhfiw3kszutTRGyigIAdYpjEJ4e2Ov3WRmXbBbdsTlS56qQLc7?purpose=fullsize)

![Image](https://images.openai.com/static-rsc-4/WLcpT_W7U5FaGvLn-OSyiwMC1mJS5yEm4JISP-QkYp_hqKd-KMPwv1oqecLl5fHMmjYW8FQkq0MxMTLJz6m3KVQrDsNtUaHSxGi5U4AUEVKqlPFxYFq5Rjn40zDI_MA26MyfwtyQA85pgVndBerCeQ7OySMw_CIPSudUbu7_OiRkdIHY7Y5Y1PsSMkV-_baF?purpose=fullsize)

![Image](https://images.openai.com/static-rsc-4/d15Ew82xaYhgxMj29DFOHXKuHkGyOSZ11VEOq6AxqckmqAzilm5qHVo5zqPiB69ots1SbiIw9BbUyYRtMlLBP_MjOwwXJBmNDBcUzvsunw1X1fkT63MHVGFHb6vaxWJVMLAgduHr-UYEB-jG2Df3L9LsWAiydvyci31vCrtBvu-E_UQ52S4-xXa-gMLSNQd0?purpose=fullsize)

![Image](https://images.openai.com/static-rsc-4/I5NGLPZfRuwmkIAI1nECim-KWSiDXGbbRGuLIgmisaRAkzgCHVWEtAi-I7GzYm0RvrHskmJUNV9IE_aXQqZevt4YCjobcJCXYiFwOt-i_s4rDnS-qqxHl_hebFLB5GjJJHgeeGWkudA8bqoFc89SBv5fAM-LEmkuTc6ZvpHmMCAhYfUgNvm836aydLiq8Fs8?purpose=fullsize)

## Phase 4 architecture

```text
Your Computer
      |
      | docker build
      v
hospital-management:v2
      |
      | docker tag
      v
Amazon ECR
      |
      v
hospital-management
      |
      ├── v1
      ├── v2
      └── later: production releases
```

Later, EKS will pull the image from ECR:

```text
GitHub
   ↓
GitHub Actions
   ↓
Docker Build
   ↓
Amazon ECR
   ↓
Amazon EKS
   ↓
Kubernetes Pods
```

---

# Step 1 — Prerequisites

On your machine, verify AWS CLI:

```bash
aws --version
```

Verify Docker:

```bash
docker --version
```

Check AWS credentials:

```bash
aws sts get-caller-identity
```

You should get something similar to:

```text
{
    "UserId": "...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/..."
}
```

If `aws sts get-caller-identity` fails, **stop here** and fix AWS CLI credentials before continuing.

---

# Step 2 — Select your AWS region

We've been using:

```text
us-east-1
```

Set it as your default region if needed:

```bash
aws configure
```

Enter:

```text
AWS Access Key ID:     <your-access-key>
AWS Secret Access Key: <your-secret-key>
Default region name:  us-east-1
Default output format: json
```

Then verify:

```bash
aws configure get region
```

Expected:

```text
us-east-1
```

**Don't put AWS access keys inside GitHub, Dockerfiles, Terraform files, or your Git repository.**

---

# Step 3 — Create an ECR repository

For this phase, we'll first create the ECR repository manually to understand the process.

Later, **Terraform will manage this repository**, so your final project remains Infrastructure-as-Code.

Create:

```bash
aws ecr create-repository \
  --repository-name hospital-management \
  --region us-east-1
```

You'll receive JSON containing information about the repository.

The important value will look like:

```text
123456789012.dkr.ecr.us-east-1.amazonaws.com/hospital-management
```

Your AWS account ID will be different.

---

# Step 4 — Verify ECR repository

Run:

```bash
aws ecr describe-repositories \
  --repository-names hospital-management \
  --region us-east-1
```

You should see:

```text
repositoryName: hospital-management
```

---

# Step 5 — Login Docker to ECR

Run:

```bash
aws ecr get-login-password \
  --region us-east-1 | \
docker login \
  --username AWS \
  --password-stdin YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com
```

Replace:

```text
YOUR_ACCOUNT_ID
```

with your AWS account ID.

You can retrieve it with:

```bash
aws sts get-caller-identity \
  --query Account \
  --output text
```

For example:

```text
123456789012
```

Then the login command becomes:

```bash
aws ecr get-login-password \
  --region us-east-1 | \
docker login \
  --username AWS \
  --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com
```

Expected:

```text
Login Succeeded
```

---

# Step 6 — Check your local Docker image

Run:

```bash
docker images
```

You should have:

```text
hospital-management    v2
```

We're going to push this image to ECR.

---

# Step 7 — Tag the image

Docker needs the ECR repository URL as the image tag.

First get your account ID:

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

Then:

```bash
echo $AWS_ACCOUNT_ID
```

Set the repository:

```bash
ECR_REPOSITORY="$AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/hospital-management"
```

Check:

```bash
echo $ECR_REPOSITORY
```

It should look like:

```text
123456789012.dkr.ecr.us-east-1.amazonaws.com/hospital-management
```

Now tag your image:

```bash
docker tag hospital-management:v2 \
  $ECR_REPOSITORY:v2
```

---

# Step 8 — Verify the tag

Run:

```bash
docker images
```

You should now see something similar to:

```text
REPOSITORY
123456789012.dkr.ecr.us-east-1.amazonaws.com/hospital-management

TAG
v2
```

You now have:

```text
Local Image
    |
    v
hospital-management:v2

        ↓ docker tag

ECR Image
    |
    v
123456789012.dkr.ecr.us-east-1.amazonaws.com/
hospital-management:v2
```

---

# Step 9 — Push image to ECR

Now:

```bash
docker push $ECR_REPOSITORY:v2
```

Docker will upload the image layers.

You should see output similar to:

```text
The push refers to repository [...]

layer1: Pushed
layer2: Pushed
layer3: Pushed

v2: digest: sha256:...
```

🎉 Your Docker image is now stored in AWS ECR.

---

# Step 10 — Verify from AWS

Run:

```bash
aws ecr list-images \
  --repository-name hospital-management \
  --region us-east-1
```

You should see:

```text
v2
```

You can also use:

```bash
aws ecr describe-images \
  --repository-name hospital-management \
  --region us-east-1
```

This will show:

* image digest
* image size
* pushed timestamp
* image tags

---

# Step 11 — Test pulling the image

Let's verify that ECR actually contains a usable image.

First remove the local ECR-tagged image:

```bash
docker rmi $ECR_REPOSITORY:v2
```

Your original image:

```text
hospital-management:v2
```

may still exist.

To test a real pull, remove both if you want:

```bash
docker rmi hospital-management:v2
docker rmi $ECR_REPOSITORY:v2
```

Then pull from ECR:

```bash
docker pull $ECR_REPOSITORY:v2
```

You should see the layers being downloaded.

---

# Step 12 — Run the ECR image

Run:

```bash
docker run -d \
  --name hospital-ecr-test \
  -p 8080:80 \
  $ECR_REPOSITORY:v2
```

Check:

```bash
docker ps
```

Test:

```bash
curl http://localhost:8080/health
```

Expected:

```text
healthy
```

Open:

```text
http://localhost:8080
```

Your application should work exactly like the local image.

This proves:

```text
Docker
   ↓
ECR
   ↓
Docker Pull
   ↓
Container
   ↓
Hospital Application
```

---

# Step 13 — Introduce proper versioning

We don't want to use only:

```text
v1
v2
```

Eventually we'll use Git versions.

For example:

```text
v1.0.0
v1.1.0
v1.2.0
```

And ECR:

```text
hospital-management
│
├── v1.0.0
├── v1.1.0
└── v1.2.0
```

We can also use the Git commit SHA:

```text
hospital-management:8f31a42
```

This becomes very useful for deployment and rollback.

For example:

```text
Production
    ↓
hospital-management:v1.1.0

Problem!
    ↓
Rollback
    ↓
hospital-management:v1.0.0
```

We'll implement this properly in the CI/CD phase.

---

# Step 14 — Clean up the test container

After testing:

```bash
docker rm -f hospital-ecr-test
```

Check:

```bash
docker ps
```

---

# Step 15 — Git

There isn't much application code to commit in this phase because the ECR repository was created in AWS.

But we should document the ECR process.

Create:

```bash
mkdir -p docs
nano docs/ecr.md
```

Add the ECR commands you used, but **never include AWS credentials**.

Then:

```bash
git add docs/ecr.md
```

Commit:

```bash
git commit -m "docs: add Amazon ECR deployment instructions"
```

Push:

```bash
git push origin feature/multistage-docker
```

---

# Important: Phase 4 is intentionally only the introduction

We're going to improve this architecture later.

Currently:

```text
Terraform
   ❌

ECR
   manually created
```

Final architecture:

```text
Terraform
    |
    +---- VPC
    |
    +---- ECR
    |
    +---- EKS
    |
    +---- IAM
    |
    +---- Networking
```

So **don't manually create everything in AWS**.

We're doing ECR manually now because it's useful to understand what is happening underneath.

---

# Phase 4 checkpoint

You should now have:

```text
┌──────────────────────────┐
│       GitHub             │
│ Hospital Management App  │
└────────────┬─────────────┘
             │
             v
       Docker Build
             │
             v
    hospital-management:v2
             │
             │ docker push
             v
┌──────────────────────────┐
│       Amazon ECR         │
│                          │
│ hospital-management      │
│          │               │
│          └── v2          │
└────────────┬─────────────┘
             │
             │ docker pull
             v
       Docker Container
             │
             v
      Hospital Website
```

Verify these commands:

```bash
aws sts get-caller-identity
```

```bash
aws ecr describe-repositories \
  --repository-names hospital-management \
  --region us-east-1
```

```bash
aws ecr list-images \
  --repository-name hospital-management \
  --region us-east-1
```

And:

```bash
curl http://localhost:8080/health
```

should return:

```text
healthy
```

---

# 🚀 Next: Phase 5 — Terraform + AWS Infrastructure

This is the **big phase**.

We'll stop manually creating infrastructure and build:

```text
                    Terraform
                        |
          +-------------+-------------+
          |             |             |
          v             v             v
         VPC           ECR           IAM
          |
    +-----+-----+
    |           |
    v           v
 Public       Private
 Subnets      Subnets
    |           |
    +-----+-----+
          |
          v
       EKS Cluster
          |
     +----+----+
     |    |    |
     v    v    v
   Node Node Node
    AZ1  AZ2  AZ3
```

We'll implement **VPC first**, then ECR through Terraform, IAM, and finally EKS. This is the foundation for the **high-availability Kubernetes architecture**.
