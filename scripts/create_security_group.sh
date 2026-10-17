#!/bin/bash
# create_security_group.sh - Creates the devops-sg security group with SSH (22) and HTTP (80) open.

set -euo pipefail

# ----- Settings -----
region="eu-west-1"
security_group_name="devops-sg"
project_tag="AutomationLab"
my_ip=$(curl -s https://checkip.amazonaws.com)   # SSH is allowed only from your current IP

# ----- Check AWS credentials -----
if ! aws_user=$(aws sts get-caller-identity --region "$region" --query 'Arn' --output text 2> /dev/null); then
  echo "ERROR: AWS CLI is not configured. Run 'aws configure' first." >&2
  exit 1
fi
echo "Running as: $aws_user"

# ----- 1. Check if the security group already exists -----
security_group_id=$(aws ec2 describe-security-groups --region "$region" \
  --filters "Name=group-name,Values=$security_group_name" \
  --query 'SecurityGroups[0].GroupId' --output text)

if [ "$security_group_id" != "None" ]; then
  echo "Security group '$security_group_name' already exists: $security_group_id"
else
  # ----- 2. Create the security group (in the default VPC) with a tag -----
  security_group_id=$(aws ec2 create-security-group --region "$region" \
    --group-name "$security_group_name" \
    --description "AutomationLab - SSH and HTTP access" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=$project_tag}]" \
    --query 'GroupId' --output text)
  echo "Security group created: $security_group_id"

  # ----- 3. Open port 22 (SSH, your IP only) and port 80 (HTTP, everyone) -----
  aws ec2 authorize-security-group-ingress --region "$region" \
    --group-id "$security_group_id" --protocol tcp --port 22 --cidr "$my_ip/32" > /dev/null
  aws ec2 authorize-security-group-ingress --region "$region" \
    --group-id "$security_group_id" --protocol tcp --port 80 --cidr 0.0.0.0/0 > /dev/null
  echo "Opened port 22 for $my_ip/32 and port 80 for 0.0.0.0/0"
fi

# ----- 4. Display the security group ID and its rules -----
echo "-----------------------------------"
echo "Security Group ID : $security_group_id"
echo "Inbound rules:"
aws ec2 describe-security-groups --region "$region" --group-ids "$security_group_id" \
  --query 'SecurityGroups[0].IpPermissions[].{Protocol:IpProtocol,Port:FromPort,Source:IpRanges[0].CidrIp}' \
  --output table
