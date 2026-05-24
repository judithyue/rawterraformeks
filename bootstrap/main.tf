terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "remote_state" {
  # checkov:skip=CKV2_AWS_62:Testing environment - notifications not needed
  # checkov:skip=CKV2_AWS_61:Testing environment - lifecycle policy not needed
  # checkov:skip=CKV_AWS_18:Testing environment - access logging not needed
  # checkov:skip=CKV_AWS_144:Testing environment - cross-region replication not needed
  # checkov:skip=CKV_AWS_145:Testing environment - SSE-S3 encryption is sufficient for lab
  bucket = var.backend_bucket

  tags = merge(var.common_tags, {
    Name = var.backend_bucket
  })
}

resource "aws_s3_bucket_versioning" "remote_state" {
  bucket = aws_s3_bucket.remote_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "remote_state" {
  bucket = aws_s3_bucket.remote_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "remote_state_block" {
  bucket = aws_s3_bucket.remote_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # This native block fixes CKV_AWS_119 without needing a skip comment
  server_side_encryption {
    enabled = true
  }

  tags = merge(var.common_tags, {
    Name = var.lock_table_name
  })
}
