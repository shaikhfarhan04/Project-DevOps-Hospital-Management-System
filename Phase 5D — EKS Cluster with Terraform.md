Yes. We are now at **Phase 5D — EKS Cluster with Terraform**.

We already have the important prerequisites in place:

```text
Terraform
   |
   +── VPC
   |    ├── 3 Public Subnets
   |    ├── 3 Private Subnets
   |    ├── Internet Gateway
   |    └── NAT Gateway
   |
   +── ECR
   |    └── hospital-management
   |
   +── IAM
        ├── EKS Cluster Role
        └── EKS Node Role
```

Now we'll create the actual **Amazon EKS cluster and managed node group**.

AWS currently lists Kubernetes **1.36, 1.35, 1.34, and 1.33** in standard support. Since 1.36 is the newest standard-supported version as of August 2026, we'll use **Kubernetes 1.36** for this project. ([AWS Documentation][1])

---

# Phase 5D Architecture

Our target is:

```text
                         AWS
                          |
                    Hospital VPC
                    10.0.0.0/16
                          |
          +---------------+---------------+
          |               |               |
         AZ-1            AZ-2            AZ-3
          |               |               |
      Private          Private          Private
      Subnet           Subnet           Subnet
          |               |               |
       EKS Node         EKS Node         EKS Node
          |               |               |
         Pod             Pod             Pod
          \               |               /
           +--------------+--------------+
                          |
                    EKS Cluster
                          |
                         ECR
                          |
                 hospital-management
```

For the initial lab:

```text
Node count:
desired = 3
min     = 3
max     = 6
```

This gives us one worker node in each AZ initially.

The managed node group supports scaling configuration and multiple subnet IDs, which is exactly what we'll use here. ([Terraform Registry][2])

---

# 5D.1 — Check your current Terraform state

Go to:

```bash
cd Hospital-Management-System/terraform
```

Run:

```bash
terraform state list
```

You should have resources similar to:

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

aws_nat_gateway.main
aws_eip.nat

aws_route_table.public
aws_route_table.private
...
```

If these exist, we're ready.

---

# 5D.2 — Add EKS variables

Open:

```bash
nano variables.tf
```

Add the following at the bottom:

```hcl
variable "eks_cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.36"
}

variable "eks_node_instance_types" {
  description = "EC2 instance types for EKS worker nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_desired_nodes" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 3
}

variable "eks_min_nodes" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 3
}

variable "eks_max_nodes" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 6
}
```

Why `t3.medium`?

For this project, we'll eventually run:

```text
Kubernetes
+
AWS Load Balancer Controller
+
Application Pods
+
Monitoring
```

A `t3.micro`/`t3.small` cluster can become cramped quickly.

`t3.medium` is a more practical lab starting point, but **it is not free-tier infrastructure**, so remember that EKS and worker nodes incur AWS charges.

---

# 5D.3 — Add the variables to `terraform.tfvars`

Open:

```bash
nano terraform.tfvars
```

Add:

```hcl
eks_cluster_version     = "1.36"
eks_node_instance_types = ["t3.medium"]

eks_desired_nodes = 3
eks_min_nodes     = 3
eks_max_nodes     = 6
```

Your file should now look roughly like:

```hcl
aws_region   = "us-east-1"
environment  = "dev"
project_name = "hospital-management"
vpc_cidr     = "10.0.0.0/16"

eks_cluster_version     = "1.36"
eks_node_instance_types = ["t3.medium"]

eks_desired_nodes = 3
eks_min_nodes     = 3
eks_max_nodes     = 6
```

---

# 5D.4 — Create `eks.tf`

Now create:

```bash
nano eks.tf
```

We'll build this in sections.

Start with:

```hcl
resource "aws_eks_cluster" "main" {
  name     = "${local.name}-eks"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_cluster_version

  access_config {
    authentication_mode = "API"
  }

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name = "${local.name}-eks"
  }
}
```

This follows the current Terraform AWS provider pattern for `aws_eks_cluster`, including the `access_config` block. ([Terraform Registry][3])

---

# 5D.5 — Understand the EKS cluster configuration

The cluster name will be:

```text
hospital-management-dev-eks
```

The Kubernetes version:

```text
1.36
```

The control plane uses:

```hcl
aws_iam_role.eks_cluster.arn
```

which we created in Phase 5C.

---

## Private subnets

We're telling EKS:

```hcl
subnet_ids = aws_subnet.private[*].id
```

So the cluster networking uses:

```text
Private AZ-1
Private AZ-2
Private AZ-3
```

This is the correct direction for our architecture.

---

# 5D.6 — EKS API endpoint

We are using:

```hcl
endpoint_private_access = true
endpoint_public_access  = true
```

This means the EKS API endpoint has both private and public access.

For our learning environment, this makes `kubectl` easier to use from your local computer.

Later, for a hardened production architecture, we can restrict API access.

---

# 5D.7 — Create the managed node group

Add to `eks.tf`:

```hcl
resource "aws_eks_node_group" "main" {
  cluster_name = aws_eks_cluster.main.name

  node_group_name = "${local.name}-nodes"

  node_role_arn = aws_iam_role.eks_node.arn

  subnet_ids = aws_subnet.private[*].id

  instance_types = var.eks_node_instance_types

  capacity_type = "ON_DEMAND"

  ami_type = "AL2023_x86_64_STANDARD"

  scaling_config {
    desired_size = var.eks_desired_nodes
    min_size     = var.eks_min_nodes
    max_size     = var.eks_max_nodes
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ec2_container_registry_read_only
  ]

  tags = {
    Name = "${local.name}-node-group"
  }
}
```

The Terraform provider supports `aws_eks_node_group` with `cluster_name`, `node_role_arn`, `subnet_ids`, scaling configuration, instance types, capacity type, and update configuration. ([Terraform Registry][2])

---

# 5D.8 — Why `AL2023`?

We're using:

```hcl
ami_type = "AL2023_x86_64_STANDARD"
```

This means our worker nodes use:

```text
Amazon Linux 2023
x86_64
```

This matches our EC2/AWS Linux learning environment and works well with EKS managed node groups.

---

# 5D.9 — Why ON_DEMAND?

We use:

```hcl
capacity_type = "ON_DEMAND"
```

instead of:

```text
SPOT
```

because this is our initial production-style architecture.

Later, we can introduce Spot nodes for cost optimization.

---

# 5D.10 — Why three nodes?

We configure:

```hcl
desired_size = 3
min_size     = 3
max_size     = 6
```

Because we have three AZs:

```text
AZ-1             AZ-2             AZ-3

Node 1           Node 2           Node 3
   |                |                |
   v                v                v
 Pods             Pods             Pods
```

If one AZ has a problem, Kubernetes can continue running workloads in the remaining AZs.

That's the beginning of our **high-availability architecture**.

---

# 5D.11 — Add EKS outputs

Open:

```bash
nano outputs.tf
```

Add:

```hcl
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "eks_cluster_endpoint" {
  description = "EKS Kubernetes API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_version" {
  description = "EKS Kubernetes version"
  value       = aws_eks_cluster.main.version
}

output "eks_node_group_name" {
  description = "EKS managed node group name"
  value       = aws_eks_node_group.main.node_group_name
}
```

---

# 5D.12 — Format Terraform

Run:

```bash
terraform fmt
```

Then:

```bash
terraform fmt -check
```

---

# 5D.13 — Validate

Run:

```bash
terraform validate
```

Expected:

```text
Success! The configuration is valid.
```

If you get an error, **don't apply anything yet**. Send me the complete error and we'll fix it first.

---

# 5D.14 — Check the EKS version with AWS

Before applying, verify that AWS offers version `1.36` in your region:

```bash
aws eks describe-addon-versions \
  --region us-east-1 \
  --kubernetes-version 1.36 \
  --query "addons[0].addonName" \
  --output text
```

You should get an addon name.

You can also check cluster versions:

```bash
aws eks describe-cluster-versions \
  --region us-east-1
```

AWS currently documents 1.36 as standard-supported, with standard support through August 2, 2027. ([AWS Documentation][1])

---

# 5D.15 — Run Terraform plan

Now:

```bash
terraform plan
```

This is an important checkpoint.

Terraform should show the EKS resources:

```text
+ aws_eks_cluster.main
+ aws_eks_node_group.main
```

It should **not** try to destroy:

```text
aws_vpc.main
aws_ecr_repository.hospital_management
aws_iam_role.eks_cluster
aws_iam_role.eks_node
```

Review the plan carefully.

You should see approximately:

```text
Plan: 2 to add, 0 to change, 0 to destroy.
```

There may be more changes if Terraform is reconciling configuration from previous steps.

---

# 5D.16 — Apply EKS

If the plan is correct:

```bash
terraform apply
```

Terraform will ask:

```text
Do you want to perform these actions?
```

Enter:

```text
yes
```

EKS creation can take several minutes.

You'll see something like:

```text
aws_eks_cluster.main: Creating...
```

Then:

```text
aws_eks_cluster.main: Creation complete
```

Then:

```text
aws_eks_node_group.main: Creating...
```

Finally:

```text
Apply complete!
```

---

# 5D.17 — Check Terraform outputs

Run:

```bash
terraform output
```

You should now see:

```text
aws_region
availability_zones
ecr_repository_name
ecr_repository_url
eks_cluster_arn
eks_cluster_endpoint
eks_cluster_name
eks_cluster_version
eks_node_group_name
eks_cluster_role_arn
eks_node_role_arn
private_subnet_ids
public_subnet_ids
vpc_id
```

Get the cluster name:

```bash
terraform output -raw eks_cluster_name
```

Expected:

```text
hospital-management-dev-eks
```

---

# 5D.18 — Verify the EKS cluster from AWS CLI

Run:

```bash
aws eks describe-cluster \
  --name "$(terraform output -raw eks_cluster_name)" \
  --region us-east-1 \
  --query "cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint}" \
  --output table
```

You want:

```text
Name                         Status     Version
------------------------------------------------
hospital-management-dev-eks  ACTIVE     1.36
```

---

# 5D.19 — Verify the node group

Run:

```bash
aws eks describe-nodegroup \
  --cluster-name "$(terraform output -raw eks_cluster_name)" \
  --nodegroup-name "$(terraform output -raw eks_node_group_name)" \
  --region us-east-1 \
  --query "nodegroup.{Name:nodegroupName,Status:status,Desired:scalingConfig.desiredSize,Min:scalingConfig.minSize,Max:scalingConfig.maxSize}" \
  --output table
```

Expected:

```text
Name                              Status    Desired    Min    Max
-----------------------------------------------------------------
hospital-management-dev-nodes    ACTIVE       3        3      6
```

---

# 5D.20 — Configure kubectl

Now we connect your local machine to EKS.

Run:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name "$(terraform output -raw eks_cluster_name)"
```

Expected:

```text
Added new context arn:aws:eks:us-east-1:ACCOUNT_ID:cluster/hospital-management-dev-eks to ...
```

---

# 5D.21 — Verify kubectl

Run:

```bash
kubectl config current-context
```

You should see something similar to:

```text
arn:aws:eks:us-east-1:123456789012:cluster/hospital-management-dev-eks
```

Then:

```bash
kubectl get nodes
```

Expected:

```text
NAME                           STATUS   ROLES    AGE   VERSION
ip-10-0-11-xxx.ec2.internal    Ready    <none>   ...   v1.36.x
ip-10-0-12-xxx.ec2.internal    Ready    <none>   ...   v1.36.x
ip-10-0-13-xxx.ec2.internal    Ready    <none>   ...   v1.36.x
```

The exact node names will be different.

---

# 5D.22 — Check all nodes

Run:

```bash
kubectl get nodes -o wide
```

You should see three nodes.

Notice their private IPs should correspond to your private networking.

---

# 5D.23 — Check system pods

Run:

```bash
kubectl get pods -A
```

You'll see Kubernetes/EKS system components.

For example:

```text
NAMESPACE     NAME                         READY
kube-system   aws-node-xxxxx               1/1
kube-system   coredns-xxxxx                1/1
kube-system   kube-proxy-xxxxx             1/1
```

Your exact list can vary by EKS platform version and managed components.

---

# 5D.24 — Verify the nodes are distributed

Run:

```bash
kubectl get nodes \
  -o custom-columns=NAME:.metadata.name,ZONE:.metadata.labels.topology\.kubernetes\.io/zone
```

You ideally want:

```text
NAME                         ZONE
------------------------------------------------
ip-10-0-11-xxx               us-east-1a
ip-10-0-12-xxx               us-east-1b
ip-10-0-13-xxx               us-east-1c
```

This is an important HA checkpoint.

Your infrastructure is now:

```text
              EKS Cluster
                   |
       +-----------+-----------+
       |           |           |
      AZ-A        AZ-B        AZ-C
       |           |           |
     Node 1      Node 2      Node 3
```

---

# 5D.25 — Verify ECR access

Remember the IAM policy:

```text
AmazonEC2ContainerRegistryPullOnly
```

was attached to the node role.

Eventually our application will use:

```text
EKS Node
   |
   | Pull
   v
ECR
   |
   v
hospital-management:v2
```

So the nodes can retrieve the application image without us putting AWS credentials inside Kubernetes.

That's an important security principle.

---

# 5D.26 — Check EKS IAM

Run:

```bash
aws iam list-attached-role-policies \
  --role-name hospital-management-dev-eks-node-role
```

You should see:

```text
AmazonEKSWorkerNodePolicy
AmazonEKS_CNI_Policy
AmazonEC2ContainerRegistryPullOnly
```

---

# 5D.27 — Check Terraform state

Run:

```bash
terraform state list | grep eks
```

You should see:

```text
aws_eks_cluster.main
aws_eks_node_group.main

aws_iam_role.eks_cluster
aws_iam_role.eks_node

aws_iam_role_policy_attachment.eks_cluster_policy
aws_iam_role_policy_attachment.eks_worker_node_policy
aws_iam_role_policy_attachment.eks_cni_policy
aws_iam_role_policy_attachment.ec2_container_registry_read_only
```

---

# 5D.28 — Git commit

Once everything works:

```bash
cd ..
```

Check:

```bash
git status
```

Then:

```bash
git add terraform/
```

Commit:

```bash
git commit -m "feat: provision EKS cluster and managed node group"
```

Push:

```bash
git push -u origin feature/terraform-infrastructure
```

---

# Phase 5D checkpoint ✅

We now have:

```text
                         AWS
                          |
                    Hospital VPC
                          |
          +---------------+---------------+
          |               |               |
         AZ-1            AZ-2            AZ-3
          |               |               |
       Private         Private         Private
       Subnet          Subnet          Subnet
          |               |               |
       EKS Node         EKS Node       EKS Node
          |               |               |
         Pod             Pod            Pod
          \               |              /
           +--------------+-------------+
                          |
                     EKS Cluster
                          |
                         ECR
                          |
                hospital-management
```

### Completed

* ✅ EKS cluster
* ✅ Kubernetes 1.36
* ✅ EKS API access
* ✅ Private subnet networking
* ✅ EKS managed node group
* ✅ 3 worker nodes
* ✅ Multi-AZ node placement
* ✅ Auto Scaling configuration `3 → 6`
* ✅ ECR pull permissions
* ✅ `kubectl` configuration
* ✅ Node verification

Terraform's current EKS resources support the cluster and managed node-group configuration we've used here. ([Terraform Registry][2])

---

# What's next?

We **should not deploy the Hospital application yet**.

First we'll complete **Phase 5E — EKS Add-ons + AWS Load Balancer Controller prerequisites**.

That will give us:

```text
EKS
 |
 +── VPC CNI
 |
 +── CoreDNS
 |
 +── kube-proxy
 |
 +── EBS CSI Driver
 |
 +── IAM / Pod permissions
 |
 └── AWS Load Balancer Controller
```

Then we'll move into the actual Kubernetes deployment:

```text
Phase 6
   ↓
Kubernetes Namespace
   ↓
Deployment
   ↓
Service
   ↓
ConfigMap
   ↓
Health Probes
   ↓
HPA
   ↓
Ingress / ALB
   ↓
Hospital Management System
```

And that's where the **Docker + ECR + EKS + Kubernetes + High Availability** pieces finally come together.

[1]: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html?utm_source=chatgpt.com "Understand the Kubernetes version lifecycle on EKS - Amazon EKS"
[2]: https://registry.terraform.io/providers/-/aws/latest/docs/resources/eks_node_group?utm_source=chatgpt.com "aws_eks_node_group | Resources | hashicorp/aws | Terraform | Terraform Registry"
[3]: https://registry.terraform.io/providers/-/aws/6.40.0/docs/resources/eks_cluster?utm_source=chatgpt.com "aws_eks_cluster | Resources | hashicorp/aws | Terraform | Terraform Registry"
