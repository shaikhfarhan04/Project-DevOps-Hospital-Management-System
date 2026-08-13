Absolutely. **Phase 5C — ECR + IAM with Terraform** is the right next step.

We already have:

* AWS region: `us-east-1`
* Terraform AWS provider: `~> 6.50`
* Environment: `dev`
* Project: `hospital-management`
* VPC: `10.0.0.0/16`
* 3 public + 3 private subnets
* Existing manually created ECR repository: `hospital-management`

Now we'll bring that existing ECR repository under Terraform management and create the IAM roles needed by EKS.

---

# Phase 5C Architecture

```text
                    Terraform
                        |
          +-------------+-------------+
          |                           |
          v                           v
     Amazon ECR                   IAM
          |                           |
          |                    +------+------+
          |                    |             |
          v                    v             v
hospital-management      EKS Cluster     EKS Nodes
          |
          |
     Docker Images
          |
          +-- v2
          +-- later releases
```

Later:

```text
GitHub Actions
      |
      v
    ECR
      |
      v
    EKS
      |
      v
 Kubernetes Pods
```

---

# 1. Go to Terraform directory

From your project root:

```bash
cd Hospital-Management-System/terraform
```

Check:

```bash
pwd
```

Then:

```bash
ls
```

You should have something similar to:

```text
versions.tf
providers.tf
variables.tf
terraform.tfvars
main.tf
outputs.tf
vpc.tf
```

---

# 2. First check the existing ECR repository

Run:

```bash
aws ecr describe-repositories \
  --repository-names hospital-management \
  --region us-east-1
```

You should see the existing repository.

This is important because **we are not going to create a second repository**.

We already have:

```text
hospital-management
```

created manually in Phase 4.

Terraform will take ownership of it.

---

# 3. Create `ecr.tf`

Create:

```bash
nano ecr.tf
```

Add:

```hcl
resource "aws_ecr_repository" "hospital_management" {
  name                 = var.project_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${local.name}-ecr"
  }
}
```

### What are we configuring?

### Repository name

```hcl
name = var.project_name
```

Since:

```hcl
project_name = "hospital-management"
```

the repository becomes:

```text
hospital-management
```

### Immutable tags

```hcl
image_tag_mutability = "IMMUTABLE"
```

This is important for release management.

Once:

```text
v1.0.0
```

is pushed, we don't want another image to overwrite that same tag.

Instead:

```text
v1.0.0 → image A
v1.1.0 → image B
v1.2.0 → image C
```

This is useful for Kubernetes rollbacks.

### Scan on push

```hcl
scan_on_push = true
```

ECR will scan images when they're pushed.

### Encryption

```hcl
encryption_type = "AES256"
```

ECR images are encrypted at rest.

---

# 4. Import the existing ECR repository

This is the most important part.

Because the repository already exists, **do not run `terraform apply` yet**.

First initialize Terraform:

```bash
terraform init
```

Then import the existing repository:

```bash
terraform import aws_ecr_repository.hospital_management hospital-management
```

Expected output will be similar to:

```text
Import successful!

The resources that were imported are shown above.
```

Now Terraform knows:

```text
AWS ECR
   |
   v
hospital-management
   |
   v
Terraform resource
aws_ecr_repository.hospital_management
```

---

# 5. Check Terraform state

Run:

```bash
terraform state list
```

You should now see resources including:

```text
aws_ecr_repository.hospital_management
```

and your existing VPC resources:

```text
aws_vpc.main
aws_internet_gateway.main
aws_subnet.public[0]
aws_subnet.public[1]
aws_subnet.public[2]
aws_subnet.private[0]
aws_subnet.private[1]
aws_subnet.private[2]
...
```

---

# 6. Check the imported repository

Run:

```bash
terraform state show aws_ecr_repository.hospital_management
```

You'll see the real AWS repository configuration.

This is a very useful Terraform skill:

```text
Existing AWS Resource
        |
        | terraform import
        v
Terraform State
        |
        v
Terraform Configuration
```

---

# 7. Run Terraform plan

Now:

```bash
terraform plan
```

Pay attention to the ECR resource.

Ideally, Terraform should **not try to destroy and recreate** the repository.

Because we imported an existing resource, Terraform should understand:

```text
AWS repository
       =
Terraform repository
```

There may be some configuration differences because the repository was created manually.

For example, Terraform may show:

```text
~ image_tag_mutability
~ image_scanning_configuration
```

That's okay—we'll review them before applying.

---

# 8. Apply the ECR configuration

If the plan only shows safe modifications to the existing ECR repository:

```bash
terraform apply
```

Review the plan.

Then:

```text
yes
```

Terraform now manages the ECR repository.

---

# 9. Add ECR outputs

Open:

```bash
nano outputs.tf
```

Add:

```hcl
output "ecr_repository_name" {
  description = "ECR repository name"
  value       = aws_ecr_repository.hospital_management.name
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.hospital_management.repository_url
}
```

Run:

```bash
terraform fmt
```

Then:

```bash
terraform validate
```

And:

```bash
terraform output
```

You should now see something like:

```text
ecr_repository_name = "hospital-management"

ecr_repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/hospital-management"
```

---

# 10. Important ECR improvement

We previously pushed:

```text
hospital-management:v2
```

to ECR.

Now that the repository is immutable, our future strategy should be:

```text
v1.0.0
v1.1.0
v1.2.0
```

rather than repeatedly pushing:

```text
latest
```

This will become important in our CI/CD pipeline.

---

# Part 2 — IAM for EKS

Now we'll create the IAM roles required by EKS.

There are two major roles we'll need:

```text
1. EKS Cluster IAM Role

2. EKS Node Group IAM Role
```

Architecture:

```text
                  EKS
                   |
        +----------+----------+
        |                     |
        v                     v
 EKS Cluster Role       Node Group Role
        |                     |
        v                     v
EKS Control Plane       EC2 Worker Nodes
                              |
                              v
                         Kubernetes Pods
```

---

# 11. Create `iam.tf`

Create:

```bash
nano iam.tf
```

Start with the EKS cluster role:

```hcl
resource "aws_iam_role" "eks_cluster" {
  name = "${local.name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "eks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${local.name}-eks-cluster-role"
  }
}
```

---

# 12. Attach the EKS cluster policy

Add:

```hcl
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
```

This gives the EKS control plane the permissions required by the managed EKS service.

---

# 13. Create the node group IAM role

Add:

```hcl
resource "aws_iam_role" "eks_node" {
  name = "${local.name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${local.name}-eks-node-role"
  }
}
```

This role will be assumed by EC2 worker nodes.

---

# 14. Attach node policies

Add:

```hcl
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
```

Then:

```hcl
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
```

And:

```hcl
resource "aws_iam_role_policy_attachment" "ec2_container_registry_read_only" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}
```

So the node role gets:

```text
EKS Worker Node Policy
          +
EKS CNI Policy
          +
ECR Pull Only
```

This is much better than giving the worker nodes broad administrative permissions.

---

# 15. Why does EKS need ECR permissions?

Eventually Kubernetes will have:

```yaml
containers:
  - name: hospital-management
    image: <ECR_URL>/hospital-management:v1.0.0
```

The worker node needs permission to pull that image.

The flow is:

```text
EKS Node
   |
   | ECR Pull
   v
Amazon ECR
   |
   v
hospital-management:v1.0.0
```

That's why we attach:

```text
AmazonEC2ContainerRegistryPullOnly
```

---

# 16. Add IAM outputs

Update `outputs.tf`:

```hcl
output "eks_cluster_role_arn" {
  description = "IAM role ARN for EKS cluster"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  description = "IAM role ARN for EKS worker nodes"
  value       = aws_iam_role.eks_node.arn
}
```

---

# 17. Format and validate

Run:

```bash
terraform fmt
```

Then:

```bash
terraform validate
```

Expected:

```text
Success! The configuration is valid.
```

---

# 18. Review the IAM plan

Run:

```bash
terraform plan
```

You should now see resources similar to:

```text
aws_ecr_repository.hospital_management
aws_iam_role.eks_cluster
aws_iam_role.eks_node

aws_iam_role_policy_attachment.eks_cluster_policy
aws_iam_role_policy_attachment.eks_worker_node_policy
aws_iam_role_policy_attachment.eks_cni_policy
aws_iam_role_policy_attachment.ec2_container_registry_read_only
```

The ECR repository should already be imported.

---

# 19. Apply IAM

If the plan looks correct:

```bash
terraform apply
```

Enter:

```text
yes
```

Terraform will create the IAM roles and policy attachments.

---

# 20. Verify IAM

Run:

```bash
aws iam get-role \
  --role-name hospital-management-dev-eks-cluster-role
```

And:

```bash
aws iam get-role \
  --role-name hospital-management-dev-eks-node-role
```

You should receive the role information.

---

# 21. Verify ECR

Run:

```bash
aws ecr describe-repositories \
  --repository-names hospital-management \
  --region us-east-1
```

Now the repository is managed by Terraform.

The relationship is:

```text
Terraform
   |
   +---- ECR
   |      |
   |      └── hospital-management
   |
   +---- IAM
          |
          +── EKS Cluster Role
          |
          └── EKS Node Role
```

---

# 22. Check Terraform state

This is an important checkpoint.

Run:

```bash
terraform state list
```

You should have resources along these lines:

```text
aws_ecr_repository.hospital_management

aws_iam_role.eks_cluster
aws_iam_role.eks_node

aws_iam_role_policy_attachment.eks_cluster_policy
aws_iam_role_policy_attachment.eks_worker_node_policy
aws_iam_role_policy_attachment.eks_cni_policy
aws_iam_role_policy_attachment.ec2_container_registry_read_only

aws_vpc.main
aws_internet_gateway.main

aws_subnet.public[0]
aws_subnet.public[1]
aws_subnet.public[2]

aws_subnet.private[0]
aws_subnet.private[1]
aws_subnet.private[2]

...
```

---

# 23. Git commit

Go back to the repository root:

```bash
cd ..
```

Check:

```bash
git status
```

Add the Terraform files:

```bash
git add terraform/
```

Commit:

```bash
git commit -m "feat: manage ECR and EKS IAM with Terraform"
```

Push:

```bash
git push -u origin feature/terraform-infrastructure
```

---

# Phase 5C checkpoint ✅

We've now completed:

```text
                    Terraform
                        |
        +---------------+---------------+
        |               |               |
        v               v               v
       VPC             ECR             IAM
        |               |               |
        |               |        +------+------+
        |               |        |             |
        |               |        v             v
        |               |    EKS Cluster    EKS Nodes
        |               |       Role          Role
        |               |
        |               └── hospital-management
        |
        +── Public Subnets
        |
        +── Private Subnets
        |
        +── NAT Gateway
        |
        └── Internet Gateway
```

### Terraform now manages:

* ✅ VPC
* ✅ Internet Gateway
* ✅ Public subnets
* ✅ Private subnets
* ✅ Route tables
* ✅ NAT Gateway
* ✅ EIP
* ✅ Existing ECR repository
* ✅ EKS cluster IAM role
* ✅ EKS node IAM role
* ✅ ECR pull permission
* ✅ EKS worker node permissions
* ✅ EKS CNI permissions

---

# Next: Phase 5D — EKS Cluster with Terraform

Now we're finally ready to create the Kubernetes cluster.

The target will be:

```text
                       AWS
                        |
                       VPC
                        |
              +---------+---------+
              |         |         |
             AZ-1      AZ-2      AZ-3
              |         |         |
           Private   Private   Private
           Subnet    Subnet    Subnet
              |         |         |
              +---------+---------+
                        |
                    EKS Cluster
                        |
                Managed Node Group
                        |
              +---------+---------+
              |         |         |
            Node 1    Node 2    Node 3
              |         |         |
             Pod       Pod       Pod
```

We'll use the **managed EKS node group**, distribute nodes across the three private subnets, and then configure `kubectl` to communicate with the cluster.

One important thing: **EKS itself can become expensive**, so once we create it, don't leave the cluster running when you're finished with your AWS lab session.
