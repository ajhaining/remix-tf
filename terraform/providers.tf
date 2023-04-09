terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.59"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

provider "aws" {
  default_tags {
    tags = {
    }
  }
}

provider "aws" {
  alias  = "global"
  region = "us-east-1"

  default_tags {
    tags = {}
  }
}