#!/usr/bin/env bash

KEYPAIR_NAME=devops
VPC_NAME=Task-2
IGW_NAME=Task-2-IGW
SUBNET_NAME=Task-2-SB
RT_NAME=Task-2-RT
SGROUP_NAME=Task-2-SG
IMAGE_ID=ami-066ef6d29e51b5811
INSTANCE_TYPE=t2.micro
REGION=us-east-1


# Check the version of AWS CLI
VERSION=$(aws --version | cut -f1 -d . | cut -f2 -d /)
if [[ $VERSION -lt 2 ]]; then
  echo -e "This script may not run successfully on AWS CLI version 1.\nSee https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
fi

# Set region
export AWS_DEFAULT_REGION=$REGION
echo -e "Set region to: $REGION \nCreating vpc with necessary components"

# Create a vpc and tag it
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --output json | grep "VpcId" | cut -f4 -d \" )
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value="$VPC_NAME"
aws ec2 wait vpc-available --vpc-id $VPC_ID
# aws ec2 describe-vpcs --vpc-id $VPC_ID

# Create an internet gateway and attach it to the vpc
IGW_ID=$(aws ec2 create-internet-gateway | grep "igw-" | cut -f4 -d \" )
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
aws ec2 create-tags --resources $IGW_ID --tags Key=Name,Value="$IGW_NAME"
# aws ec2 describe-internet-gateways --internet-gateway-id $IGW_ID

# Create a subnet within the vpc and modify it so that new instances within it will be public on launch
SUBNET_ID=$(aws ec2 create-subnet --cidr-block 10.0.1.0/24 --vpc-id $VPC_ID | grep SubnetId | cut -f4 -d \" )
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_ID --map-public-ip-on-launch
aws ec2 create-tags --resources $SUBNET_ID --tags Key=Name,Value="$SUBNET_NAME"
# aws ec2 describe-subnets --subnet-id $SUBNET_ID

# Create a route table in the vpc
RT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID | grep "rtb-" | cut -f4 -d \" )
aws ec2 create-tags --resources $RT_ID --tags Key=Name,Value="$RT_NAME"
# aws ec2 describe-route-tables --route-table-id $RT_ID

# Create a route to the internet gateway and attach table to subnet
aws ec2 create-route --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --route-table-id $RT_ID
aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUBNET_ID

echo "Please wait a moment..."
aws ec2 wait vpc-available --vpc-ids $VPC_ID
echo -e "$VPC_ID\n$IGW_ID\n$SUBNET_ID and\n$RT_ID are ready\nCreating new key pair..."

# Create a new key pair
# CHECK IF KEY PAIR ALREADY EXISTS
if [ ! -f "devops.pem" ]; then
  # echo 'Creating new key pair'
  aws ec2 create-key-pair --key-name $KEYPAIR_NAME --query 'KeyMaterial' --output text > $KEYPAIR_NAME.pem
  chmod 400 devops.pem
  aws ec2 wait key-pair-exists --key-names $KEYPAIR_NAME
  KEYPAIR_ID=$(aws ec2 describe-key-pairs  --key-names $KEYPAIR_NAME | grep KeyPairId | cut -f4 -d \" )
  echo "$KEYPAIR_NAME created"
else
  echo "$KEYPAIR_NAME already exists"
  KEYPAIR_ID=$(aws ec2 describe-key-pairs  --key-names $KEYPAIR_NAME | grep KeyPairId | cut -f4 -d \" )
fi

# Create a security group and allow SSH and HTTP access from anywhere. NOTE: not advisable in production!
aws ec2 create-security-group --group-name $SGROUP_NAME --description "$SGROUP_NAME security group for SSH access" --vpc-id $VPC_ID
SGROUP_ID=$(aws ec2 describe-security-groups --filters Name=description,Values="$SGROUP_NAME security group for SSH access" | grep GroupId | cut -f4 -d \" )
aws ec2 authorize-security-group-ingress --group-id $SGROUP_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SGROUP_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 wait security-group-exists --group-ids $SGROUP_ID
echo "Security group: $SGROUP_NAME $SGROUP_ID created"

# Create an ec2 instance running Ubuntu 18 AMI on t2.micro
INSTANCE_ID=$(aws ec2 run-instances --image-id $IMAGE_ID  --count 1 --instance-type $INSTANCE_TYPE --key-name $KEYPAIR_NAME --security-group-ids $SGROUP_ID --subnet-id $SUBNET_ID  | grep InstanceId | cut -f4 -d \" )
aws ec2 create-tags --resources $INSTANCE_ID --tags Key=Role,Value="Web-Server"
echo "Creating instance"
echo "This could take a few moments..."
aws ec2 wait instance-exists --instance-ids $INSTANCE_ID
PUB_IPADDRESS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID | grep PublicIpAddress | cut -f4 -d \" )
echo -e "\nSuccess!"
echo "Instance $INSTANCE_ID created with public IP address: $PUB_IPADDRESS"