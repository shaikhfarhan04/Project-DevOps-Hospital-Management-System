
# Phase 5 — Terraform + AWS Infrastructure

Our target architecture is:

```text
                         AWS
                          |
                       Region
                     us-east-1
                          |
                         VPC
                  10.0.0.0/16
                          |
          +---------------+---------------+
          |               |               |
        AZ-1            AZ-2            AZ-3
          |               |               |
     Public Subnet   Public Subnet   Public Subnet
          |               |               |
     Private Subnet  Private Subnet  Private Subnet
          |               |               |
          +---------------+---------------+
                          |
                     EKS Cluster
                          |
                +---------+---------+
                |         |         |
              Node 1    Node 2    Node 3
                |         |         |
               Pod       Pod       Pod
```

We'll eventually have Terraform manage:

```text
VPC
├── Internet Gateway
├── Public Subnets
├── Private Subnets
├── Route Tables
├── NAT Gateway
├── Security Groups
│
├── ECR
│
├── IAM
│
└── EKS
    └── Managed Node Group
```

## Phase 5 implementation order

We'll split Phase 5 itself into smaller checkpoints:

**5A. Terraform project setup** ← start here
**5B. VPC and networking**
**5C. ECR with Terraform**
**5D. IAM**
**5E. EKS cluster**
**5F. Terraform outputs and validation**
**5G. Terraform destroy/cleanup**

This way, if something fails, we'll know exactly which part caused it.

---

# 5A — Terraform Project Setup

## Step 1 — Create Terraform branch

From your project:

```bash
cd Hospital-Management-System
```

Check:

```bash
git status
```

Then:

```bash
git checkout develop
```

Update it:

```bash
git pull origin develop
```

Create the Terraform branch:

```bash
git checkout -b feature/terraform-infrastructure
```

Verify:

```bash
git branch
```

You should have:

```text
* feature/terraform-infrastructure
  develop
  feature/docker
  feature/multistage-docker
  main
```

---

# Step 2 — Check Terraform

Run:

```bash
terraform version
```

You should see your installed Terraform version.

Also verify AWS CLI:

```bash
aws --version
```

And AWS credentials:

```bash
aws sts get-caller-identity
```

Make sure this succeeds before continuing.

---

# Step 3 — Create Terraform directory structure

From the repository root:

```bash
mkdir -p terraform
```

We'll eventually have:

```text
terraform/
├── versions.tf
├── providers.tf
├── variables.tf
├── terraform.tfvars
├── outputs.tf
│
├── vpc.tf
├── ecr.tf
├── iam.tf
└── eks.tf
```

Don't create all of them yet.

We'll build them one by one.

---

# Step 4 — Create `versions.tf`

Create:

```bash
nano terraform/versions.tf
```

Use:

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.50"
    }
  }
}
```

### Why this file?

It tells Terraform:

```text
Terraform
   |
   +-- Terraform >= 1.6
   |
   +-- AWS provider ~> 6.50
```

This prevents Terraform from unexpectedly using an incompatible provider version.

---

# Step 5 — Create `providers.tf`

Create:

```bash
nano terraform/providers.tf
```

Add:

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Hospital-Management-System"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
```

Notice we're not hardcoding:

```hcl
region = "us-east-1"
```

Instead:

```hcl
region = var.aws_region
```

We'll define that variable next.

---

# Step 6 — Create `variables.tf`

Create:

```bash
nano terraform/variables.tf
```

Add:

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "hospital-management"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
```

Now our configuration is parameterized.

For example:

```text
aws_region
    |
    +-- us-east-1

environment
    |
    +-- dev

project_name
    |
    +-- hospital-management

vpc_cidr
    |
    +-- 10.0.0.0/16
```

---

# Step 7 — Create `terraform.tfvars`

Create:

```bash
nano terraform/terraform.tfvars
```

Add:

```hcl
aws_region  = "us-east-1"
environment = "dev"
project_name = "hospital-management"
vpc_cidr    = "10.0.0.0/16"
```

### Important

This file doesn't contain credentials, so it's fine for the project.

However, later we'll decide whether to commit it or use environment-specific `.tfvars` files.

**Never put AWS access keys here.**

---

# Step 8 — Create `main.tf`

Create:

```bash
nano terraform/main.tf
```

Add:

```hcl
locals {
  name = "${var.project_name}-${var.environment}"
}
```

This creates a reusable name:

```text
hospital-management-dev
```

Later we can have:

```text
hospital-management-dev
hospital-management-staging
hospital-management-prod
```

This will become important when we implement **multi-stage environments**.

---

# Step 9 — Create `outputs.tf`

Create:

```bash
nano terraform/outputs.tf
```

For now:

```hcl
output "project_name" {
  value = local.name
}

output "aws_region" {
  value = var.aws_region
}
```

Later we'll add:

```text
VPC ID
Subnet IDs
ECR URL
EKS cluster name
EKS endpoint
Load balancer
```

---

# Step 10 — Initialize Terraform

Now:

```bash
cd terraform
```

Run:

```bash
terraform init
```

You should see something similar to:

```text
Initializing the backend...

Initializing provider plugins...

- Finding hashicorp/aws versions matching "~> 6.50"...
- Installing hashicorp/aws...

Terraform has been successfully initialized!
```

---

# Step 11 — Format Terraform

Run:

```bash
terraform fmt
```

You should see files formatted.

Check:

```bash
terraform fmt -check
```

If there is no output, that's good.

---

# Step 12 — Validate Terraform

Run:

```bash
terraform validate
```

Expected:

```text
Success! The configuration is valid.
```

At this point, Terraform understands our configuration.

But we haven't created any AWS resources yet.

---

# Step 13 — Run Terraform plan

Run:

```bash
terraform plan
```

Because we only have variables and locals currently, you should see something similar to:

```text
No changes. Your infrastructure matches the configuration.
```

That's expected.

---

# 5B — Build the VPC

Now we're going to create the AWS network.

Our target:

```text
VPC
10.0.0.0/16
│
├── Public Subnet AZ-1
│   10.0.1.0/24
│
├── Public Subnet AZ-2
│   10.0.2.0/24
│
├── Public Subnet AZ-3
│   10.0.3.0/24
│
├── Private Subnet AZ-1
│   10.0.11.0/24
│
├── Private Subnet AZ-2
│   10.0.12.0/24
│
└── Private Subnet AZ-3
    10.0.13.0/24
```

This gives us three Availability Zones.

---

# Step 14 — Create `vpc.tf`

Create:

```bash
nano vpc.tf
```

Add:

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name}-igw"
  }
}
```

---

# Step 15 — Public subnets

Add to `vpc.tf`:

```hcl
resource "aws_subnet" "public" {
  count = 3

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-${count.index + 1}"

    "kubernetes.io/role/elb" = "1"
  }
}
```

This creates:

```text
Public subnet 1 → 10.0.1.0/24
Public subnet 2 → 10.0.2.0/24
Public subnet 3 → 10.0.3.0/24
```

The tag:

```text
kubernetes.io/role/elb
```

will later help Kubernetes/AWS identify subnets suitable for internet-facing load balancers.

---

# Step 16 — Private subnets

Add:

```hcl
resource "aws_subnet" "private" {
  count = 3

  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 11}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${local.name}-private-${count.index + 1}"

    "kubernetes.io/role/internal-elb" = "1"
  }
}
```

This gives:

```text
10.0.11.0/24
10.0.12.0/24
10.0.13.0/24
```

---

# Step 17 — Public route table

Add:

```hcl
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name}-public-rt"
  }
}
```

Then associate it:

```hcl
resource "aws_route_table_association" "public" {
  count = 3

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
```

Traffic flow becomes:

```text
Public Subnet
      |
      v
Route Table
      |
      v
Internet Gateway
      |
      v
Internet
```

---

# Step 18 — NAT Gateway

For our EKS architecture, private subnets need outbound internet access for things such as pulling container images and updates.

We'll create one NAT Gateway initially to control cost.

Add:

```hcl
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [
    aws_internet_gateway.main
  ]

  tags = {
    Name = "${local.name}-nat"
  }
}
```

### Important HA note

A **single NAT Gateway is not fully highly available**.

For production HA, we'd normally use:

```text
AZ-1 → NAT Gateway 1
AZ-2 → NAT Gateway 2
AZ-3 → NAT Gateway 3
```

That costs more.

Since you're building this as a learning project and AWS costs matter, we'll initially use **one NAT Gateway**, then later I'll show you how to switch to one per AZ for stronger HA.

The **EKS nodes and application pods themselves will still be distributed across multiple AZs**.

---

# Step 19 — Private route table

Add:

```hcl
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${local.name}-private-rt"
  }
}
```

Associate:

```hcl
resource "aws_route_table_association" "private" {
  count = 3

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

Now:

```text
Private Subnet
      |
      v
Private Route Table
      |
      v
NAT Gateway
      |
      v
Internet Gateway
      |
      v
Internet
```

But the internet cannot directly initiate a connection to the private subnet.

That's exactly what we want for EKS worker nodes.

---

# Step 20 — Add VPC outputs

Update `outputs.tf`:

```hcl
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "availability_zones" {
  value = data.aws_availability_zones.available.names
}
```

---

# Step 21 — Format

From `terraform/`:

```bash
terraform fmt
```

---

# Step 22 — Validate

```bash
terraform validate
```

Expected:

```text
Success! The configuration is valid.
```

---

# Step 23 — Plan

Now:

```bash
terraform plan
```

Terraform should show resources such as:

```text
aws_vpc.main
aws_internet_gateway.main
aws_subnet.public
aws_subnet.private
aws_route_table.public
aws_route_table.private
aws_nat_gateway.main
aws_eip.nat
```

**Don't run `terraform apply` yet if your plan shows unexpected resources or errors.**

We should inspect the plan first.

---

# Step 24 — Create the infrastructure

If the plan looks correct:

```bash
terraform apply
```

Terraform will ask:

```text
Do you want to perform these actions?
  Only 'yes' will be accepted to approve.
```

Enter:

```text
yes
```

Terraform should create the network.

---

# Step 25 — Verify Terraform outputs

Run:

```bash
terraform output
```

You should see:

```text
availability_zones
private_subnet_ids
project_name
public_subnet_ids
vpc_id
aws_region
```

Get only the VPC:

```bash
terraform output vpc_id
```

---

# Step 26 — Verify from AWS CLI

Check VPC:

```bash
aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=hospital-management-dev-vpc" \
  --region us-east-1
```

Check subnets:

```bash
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" \
  --region us-east-1
```

You should see six subnets:

```text
3 public
3 private
```

---

# Step 27 — Understand what we've built

At the end of this part:

```text
                   AWS
                    |
                   VPC
              10.0.0.0/16
                    |
       +------------+------------+
       |            |            |
      AZ1          AZ2          AZ3
       |            |            |
    Public       Public       Public
    10.0.1/24    10.0.2/24    10.0.3/24
       |            |            |
       +------------+------------+
                    |
                 Internet
                    |
              Internet Gateway

       +------------+------------+
       |            |            |
      AZ1          AZ2          AZ3
       |            |            |
    Private      Private      Private
    10.0.11/24   10.0.12/24   10.0.13/24
       \            |            /
        \           |           /
             NAT Gateway
```

This is the network on which we'll build EKS.

---

# Step 28 — Git commit

From the project root:

```bash
cd ..
```

Check:

```bash
git status
```

Add Terraform:

```bash
git add terraform/
```

Commit:

```bash
git commit -m "feat: provision AWS VPC infrastructure with Terraform"
```

Push:

```bash
git push -u origin feature/terraform-infrastructure
```

---

# ⚠️ Important cost warning

At this point you've created a **NAT Gateway**.

NAT Gateways are not free-tier-style resources and can incur charges even when you're not actively using them.

For your learning project, don't leave AWS infrastructure running unnecessarily.

When we're completely finished with a lab session, we can eventually use:

```bash
terraform destroy
```

But **don't destroy it yet** because we'll use this VPC for ECR/EKS.

Also, before moving to EKS, we'll decide whether to keep one NAT Gateway for cost savings or use one per AZ for stronger HA.

---

# Phase 5 checkpoint

At this point, we have completed:

```text
✅ Terraform installed
✅ AWS provider configured
✅ Terraform variables
✅ Terraform initialization
✅ Terraform validation
✅ AWS VPC
✅ Internet Gateway
✅ 3 Public Subnets
✅ 3 Private Subnets
✅ Route Tables
✅ NAT Gateway
✅ EIP
✅ Kubernetes subnet tags
```

Our infrastructure is now ready for the next layer:

```text
Terraform
   |
   v
AWS VPC
   |
   +---- Public Subnets
   |
   +---- Private Subnets
   |
   +---- NAT Gateway
   |
   +---- Internet Gateway
             |
             v
        Next: ECR
             |
             v
        Next: IAM
             |
             v
        Next: EKS
```

## Next: Phase 5C — ECR + IAM with Terraform

The next step should **not** be EKS immediately. We'll first move the ECR repository we created manually in Phase 4 into Terraform management and then create the IAM roles/policies required by EKS.

That will give us:

```text
Terraform
   |
   +── VPC
   |
   +── ECR
   |
   +── IAM
   |
   └── EKS
```

and eventually:

```text
GitHub
   ↓
GitHub Actions
   ↓
Docker
   ↓
ECR
   ↓
EKS
   ↓
Kubernetes
   ↓
AWS ALB
   ↓
Users
```
