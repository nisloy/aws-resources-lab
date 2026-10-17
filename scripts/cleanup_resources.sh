#!/bin/bash
# cleanup_resources.sh - Deletes everything the other scripts created, found by the tag Project=AutomationLab.

set -euo pipefail

# ----- Settings -----
region="eu-west-1"
project_tag="AutomationLab"
security_group_name="devops-sg"
key_name="automationlab-key"
bucket_prefix="amuza-automationlab"

# ----- Check AWS credentials -----
if ! aws_user=$(aws sts get-caller-identity --region "$region" --query 'Arn' --output text 2> /dev/null); then
  echo "ERROR: AWS CLI is not configured. Run 'aws configure' first." >&2
  exit 1
fi
echo "Running as: $aws_user"

# ----- 1. Terminate EC2 instances tagged Project=AutomationLab -----
instance_ids=$(aws ec2 describe-instances --region "$region" \
  --filters "Name=tag:Project,Values=$project_tag" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)

if [ -n "$instance_ids" ]; then
  echo "Terminating instance(s): $instance_ids"
  # shellcheck disable=SC2086  # word splitting is wanted: one argument per instance ID
  aws ec2 terminate-instances --region "$region" --instance-ids $instance_ids > /dev/null
  # shellcheck disable=SC2086
  aws ec2 wait instance-terminated --region "$region" --instance-ids $instance_ids
  echo "Instance(s) terminated."
else
  echo "No tagged EC2 instances found."
fi

# ----- 2. Delete the security group (only if it has our tag) -----
security_group_id=$(aws ec2 describe-security-groups --region "$region" \
  --filters "Name=tag:Project,Values=$project_tag" "Name=group-name,Values=$security_group_name" \
  --query 'SecurityGroups[0].GroupId' --output text)

if [ "$security_group_id" != "None" ]; then
  aws ec2 delete-security-group --region "$region" --group-id "$security_group_id"
  echo "Security group deleted: $security_group_id"
else
  echo "No tagged security group found."
fi

# ----- 3. Delete the key pair and the local .pem file -----
if aws ec2 describe-key-pairs --region "$region" --key-names "$key_name" > /dev/null 2>&1; then
  aws ec2 delete-key-pair --region "$region" --key-name "$key_name"
  rm -f "$key_name.pem"
  echo "Key pair deleted: $key_name"
else
  echo "No key pair named '$key_name' found."
fi

# ----- 4. Empty and delete the S3 bucket (only if it has our tag) -----
account_id=$(aws sts get-caller-identity --query 'Account' --output text)
bucket_name="$bucket_prefix-$account_id"

bucket_tag=$(aws s3api get-bucket-tagging --bucket "$bucket_name" \
  --query "TagSet[?Key=='Project'].Value" --output text 2> /dev/null || true)

if [ "$bucket_tag" = "$project_tag" ]; then
  # Versioning is on, so every version and delete marker must be removed first
  aws s3api list-object-versions --bucket "$bucket_name" \
    --query '[Versions,DeleteMarkers][][].[Key,VersionId]' --output text |
  while read -r file_key version_id; do
    aws s3api delete-object --bucket "$bucket_name" --key "$file_key" --version-id "$version_id" > /dev/null
    echo "Deleted $file_key (version $version_id)"
  done
  aws s3api delete-bucket --bucket "$bucket_name" --region "$region"
  echo "Bucket deleted: $bucket_name"
else
  echo "No tagged bucket named '$bucket_name' found."
fi

echo "-----------------------------------"
echo "Cleanup complete."
