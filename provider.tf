terraform {
  backend "s3" {
    bucket         = "terraform-tf-state-file-bucket-12"
    key            = "terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
  }
}