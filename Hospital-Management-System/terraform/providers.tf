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