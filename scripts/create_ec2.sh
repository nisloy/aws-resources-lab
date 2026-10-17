#!/bin/bash
# create_ec2.sh - Creates a key pair and launches a tagged Amazon Linux 2 EC2 instance.

set -euo pipefail

# ----- Settings -----
region="eu-west-1"
key_name="automationlab-key"
instance_name="automationlab-web"
instance_type="t3.micro"
security_group_name="devops-sg"
project_tag="AutomationLab"

# ----- Check AWS credentials -----
if ! aws_user=$(aws sts get-caller-identity --region "$region" --query 'Arn' --output text 2> /dev/null); then
  echo "ERROR: AWS CLI is not configured. Run 'aws configure' first." >&2
  exit 1
fi
echo "Running as: $aws_user"

# ----- 1. Create the key pair (skip if it already exists) -----
if aws ec2 describe-key-pairs --key-names "$key_name" --region "$region" > /dev/null 2>&1; then
  echo "Key pair '$key_name' already exists - reusing it."
else
  aws ec2 create-key-pair --key-name "$key_name" --region "$region" \
    --query 'KeyMaterial' --output text > "$key_name.pem"
  chmod 400 "$key_name.pem"
  echo "Key pair created and saved to $key_name.pem"
fi

# ----- 2. Get the latest free-tier Amazon Linux 2 AMI -----
ami_id=$(aws ssm get-parameters --region "$region" \
  --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
  --query 'Parameters[0].Value' --output text)
echo "Using AMI: $ami_id"

# ----- 3. Find the security group (created by create_security_group.sh) -----
security_group_id=$(aws ec2 describe-security-groups --region "$region" \
  --filters "Name=group-name,Values=$security_group_name" \
  --query 'SecurityGroups[0].GroupId' --output text)

if [ "$security_group_id" = "None" ]; then
  echo "ERROR: Security group '$security_group_name' not found. Run create_security_group.sh first." >&2
  exit 1
fi

# ----- 4. Launch the instance with tags -----
instance_id=$(aws ec2 run-instances --region "$region" \
  --image-id "$ami_id" \
  --instance-type "$instance_type" \
  --key-name "$key_name" \
  --security-group-ids "$security_group_id" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instance_name},{Key=Project,Value=$project_tag}]" \
  --query 'Instances[0].InstanceId' --output text)

echo "Instance $instance_id launched. Waiting for it to start..."
aws ec2 wait instance-running --instance-ids "$instance_id" --region "$region"

# ----- 5. Print the instance ID and public IP -----
public_ip=$(aws ec2 describe-instances --instance-ids "$instance_id" --region "$region" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo "-----------------------------------"
echo "Instance ID : $instance_id"
echo "Public IP   : $public_ip"
echo "-----------------------------------"
