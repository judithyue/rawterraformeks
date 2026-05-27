# Terraform Backend Bootstrap

This repository uses a Terraform bootstrap workflow to provision the remote backend resources required for Terraform state management.

The bootstrap setup creates:
- An S3 bucket for Terraform state files
- A DynamoDB table for Terraform state locking

These resources are provisioned by the workflow defined in `.github/workflows/terraform-bootstrap.yml` and the Terraform configuration in `bootstrap/`.

## Prerequisites

1. AWS credentials configured as GitHub secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

2. The target AWS region is currently set to `ap-southeast-1` in the bootstrap workflow and `bootstrap/variables.tf`.

3. Ensure GitHub Actions can access the repository and has permission to run workflows.

## Bootstrap Workflow

### 1. Run the bootstrap plan

This step validates the bootstrap Terraform configuration and creates a plan artifact.

- In GitHub Actions, run the `Terraform Bootstrap` workflow with the input `action: plan`.
- Or locally inside the `bootstrap/` folder:

```bash
cd bootstrap
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
```

### 2. Apply the bootstrap plan

This step provisions the S3 backend bucket and DynamoDB lock table.

- In GitHub Actions, run the `Terraform Bootstrap` workflow with the input `action: apply`.
- Or locally inside the `bootstrap/` folder:

```bash
cd bootstrap
terraform init
terraform apply -auto-approve tfplan
```

## Bootstrap Terraform configuration

The bootstrap module defines:
- `bootstrap/main.tf`:
  - `aws_s3_bucket.remote_state`
  - `aws_s3_bucket_versioning.remote_state`
  - `aws_s3_bucket_server_side_encryption_configuration.remote_state`
  - `aws_s3_bucket_public_access_block.remote_state_block`
  - `aws_dynamodb_table.terraform_locks`
- `bootstrap/variables.tf`:
  - `backend_bucket` default: `bq-mightycapstone-terraform-state`
  - `lock_table_name` default: `bq-mightycapstone-terraform-locks`
  - `aws_region` default: `ap-southeast-1`
- `bootstrap/outputs.tf` exposes the bucket and lock table names.

## Post-bootstrap

After applying the bootstrap workflow, the Terraform environment workflows in `.github/workflows/terraform-environments.yml` use the following backend configuration:
- `bucket`: `bq-mightycapstone-terraform-state`
- `key`: `state/<environment>/terraform.tfstate`
- `dynamodb_table`: `bq-mightycapstone-terraform-locks`
- `region`: `ap-southeast-1`

## Notes

- The bootstrap workflow is triggered by changes in `bootstrap/**` or `.github/workflows/terraform-bootstrap.yml` on `main`.
- The backend bucket and lock table names are defined in `bootstrap/variables.tf` and can be changed there if necessary.
- If you change the backend bucket or lock table name, update the environment workflows accordingly.
