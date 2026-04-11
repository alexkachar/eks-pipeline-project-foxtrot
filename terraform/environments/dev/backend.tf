terraform {
  backend "s3" {
    bucket         = "alexanderkachar-terraform-state"
    key            = "eks-pipeline-project-foxtrot/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
