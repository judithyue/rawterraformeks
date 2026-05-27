bucket         = "bq-mightycapstone-terraform-state"
key            = "state/dev/terraform.tfstate"
region         = "ap-southeast-1"
dynamodb_table = "bq-mightycapstone-terraform-locks"
encrypt        = true
