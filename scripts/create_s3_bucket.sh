#!/bin/bash
# create_s3_bucket.sh - Creates a unique S3 bucket with versioning, a bucket policy and a welcome.txt file.

set -euo pipefail

# ----- Settings -----
region="eu-west-1"
bucket_prefix="amuza-automationlab"
project_tag="AutomationLab"
file_to_upload="welcome.txt"

# ----- Check AWS credentials -----
if ! aws_user=$(aws sts get-caller-identity --region "$region" --query 'Arn' --output text 2> /dev/null); then
  echo "ERROR: AWS CLI is not configured. Run 'aws configure' first." >&2
  exit 1
fi
echo "Running as: $aws_user"

# Bucket names must be unique worldwide, so we add the AWS account ID to the name
account_id=$(aws sts get-caller-identity | jq -r '.Account')
bucket_name="$bucket_prefix-$account_id"

# ----- 1. Create the bucket (skip if it already exists) -----
if aws s3api head-bucket --bucket "$bucket_name" > /dev/null 2>&1; then
  echo "Bucket '$bucket_name' already exists - reusing it."
else
  aws s3api create-bucket --bucket "$bucket_name" --region "$region" \
    --create-bucket-configuration LocationConstraint="$region" > /dev/null
  echo "Bucket created: $bucket_name"
fi

# ----- 2. Tag the bucket (the cleanup script uses this tag) -----
aws s3api put-bucket-tagging --bucket "$bucket_name" \
  --tagging "TagSet=[{Key=Project,Value=$project_tag}]"

# ----- 3. Enable versioning -----
aws s3api put-bucket-versioning --bucket "$bucket_name" \
  --versioning-configuration Status=Enabled
echo "Versioning enabled."

# ----- 4. Add a simple bucket policy: refuse any request that is not HTTPS -----
policy=$(cat <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::$bucket_name",
        "arn:aws:s3:::$bucket_name/*"
      ],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    }
  ]
}
POLICY
)
aws s3api put-bucket-policy --bucket "$bucket_name" --policy "$policy"
echo "Bucket policy applied (HTTPS only)."

# ----- 5. Create and upload welcome.txt -----
echo "Welcome to AutomationLab! Uploaded by $aws_user on $(date)" > "$file_to_upload"
aws s3 cp "$file_to_upload" "s3://$bucket_name/$file_to_upload" > /dev/null
echo "Uploaded $file_to_upload"

# ----- 6. Show the result -----
echo "-----------------------------------"
echo "Bucket name : $bucket_name"
echo "Region      : $region"
echo "Versioning  : $(aws s3api get-bucket-versioning --bucket "$bucket_name" --query 'Status' --output text)"
echo "Files in bucket:"
aws s3 ls "s3://$bucket_name/"
echo "-----------------------------------"
