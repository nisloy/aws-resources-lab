# Automate AWS Resource Creation with Bash

Bash scripts that use the AWS CLI to create an EC2 instance, a security group and an S3 bucket, and to clean them up.

## Purpose of each script

| Script | Purpose |
|---|---|
| `create_security_group.sh` | Creates the `devops-sg` security group, opens port 22 (SSH, my IP only) and port 80 (HTTP), and displays the group ID and rules. |
| `create_ec2.sh` | Creates a key pair, launches a free-tier Amazon Linux 2 instance tagged `Project=AutomationLab`, and prints the instance ID and public IP. |
| `create_s3_bucket.sh` | Creates a uniquely named S3 bucket, enables versioning, applies a bucket policy (HTTPS only) and uploads `welcome.txt`. |
| `cleanup_resources.sh` | Deletes all resources tagged `Project=AutomationLab` (instance, security group, key pair and bucket). |

## Setup

1. Install AWS CLI v2 and configure it with an IAM user:
   ```bash
   aws configure        # region: eu-west-1, output: json
   ```
2. Verify the setup:
   ```bash
   aws sts get-caller-identity
   aws configure list
   ```
3. Make the scripts executable:
   ```bash
   cd scripts
   chmod 700 *.sh
   ```

## Execution

Run the scripts in this order:

```bash
./create_security_group.sh
./create_ec2.sh
./create_s3_bucket.sh
./cleanup_resources.sh    # when finished
```

Screenshots of each successful run are in the `screenshots/` folder.

## Challenges faced and how they were resolved

1. **EC2 script ran before the security group existed** – The first run failed to find `devops-sg`. I added a check that stops with a clear error and ran `create_security_group.sh` first.
2. **S3 bucket names must be globally unique** – I added my AWS account ID to the bucket name.
3. **Bucket policy blocked by Block Public Access** – A public policy would be rejected, so I used a policy that denies non-HTTPS requests.
4. **Creating a bucket in `eu-west-1`** – Regions other than `us-east-1` need `LocationConstraint`, so I added it to `create-bucket`.
5. **Deleting a versioned bucket** – All object versions must be deleted first, so the cleanup script removes every version before deleting the bucket.
6. **Security group in use during cleanup** – The cleanup script waits until the instance is terminated before deleting the security group.
