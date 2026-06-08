terraform {
  backend "s3" {
    bucket         = "rnd-terraform-ansible-20260608"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    use_lockfile   = true
  }
}
