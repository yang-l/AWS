#!/usr/bin/env bash

## This script is using AWS CLI to create a EC2 instance

## Require
## AWS CLI - http://aws.amazon.com/cli/

# $1 - AWS parameter override file

. `cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd`/../../lib/shared.func
. `cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd`/../../lib/aws.func $1 # AWS setup
. `cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd`/../../lib/folder.func # @ $_WORK_DIR

## Define variables
PIP=`which pip`
#VIRTUALENV="$_WORK_DIR_"/virenv
VIRTUALENV=~/virenv

# install virtualenv
$PIP install --upgrade --user virtualenv -q || ( console_output "ERROR" "Failed to install virtuallenv using pip, existing" && exit 1 )

# create a virtualenv
mkdir -p "$VIRTUALENV"
~/.local/bin/virtualenv $VIRTUALENV -q
. $VIRTUALENV/bin/activate # inside virtualenv

# parameters
AMI_ID="ami-1ecae776"
AWS="`which python` "${VIRTUALENV}"/bin/aws"
KEY_PAIR="key-pair_`date +"%F_%H-%M-%S_%Z"`"
KEY_PAIR_FILE="${VIRTUALENV}/${KEY_PAIR}.pem"
SEC_GRP="sec-grp_`date +"%F_%H-%M-%S_%Z"`"
SUBNET="192.168.10.1/28"

# store output ids
declare -A AWS_OUTPUT # store AWS output IDs

# create configuration file and export
cat <<EOF >  "$VIRTUALENV/aws.cfg"
[default]
region = us-east-1
output = text
EOF
export AWS_CONFIG_FILE="$VIRTUALENV/aws.cfg" # override default location

# install awscli in virtualenv
pip install --upgrade awscli -q || ( console_output "ERROR" "Failed to install awscli via pip in virtualenv, existing" && deactivate && exit 1 )

# create VPC
AWS_OUTPUT[VPC_ID]=$(($AWS ec2 create-vpc --cidr-block "${SUBNET}" || ( console_output "ERROR" "Failed to create VPC" && deactivate && exit 1 )) | awk '{print $6;}')

# create internet gateway
AWS_OUTPUT[IG_ID]=$(($AWS ec2 create-internet-gateway || ( console_output "ERROR" "Failed to create Internet Gateway" && deactivate && exit 1 )) | awk '{print $2}')

# attach IG to VPC
($AWS ec2 attach-internet-gateway --internet-gateway-id "${AWS_OUTPUT[IG_ID]}" --vpc-id "${AWS_OUTPUT[VPC_ID]}"  || ( console_output "ERROR" "Failed to attach IG (${AWS_OUTPUT[IG_ID]}) to VPC (${AWS_OUTPUT[VPC_ID]})" && deactivate && exit 1 ))

# create subnet
AWS_OUTPUT[SUBNET_ID]=$(($AWS ec2 create-subnet --vpc-id ${AWS_OUTPUT[VPC_ID]} --cidr-block "${SUBNET}" || ( console_output "ERROR" "Failed to create SUBNET" && deactivate && exit 1 )) | awk '{print $6;}')

# add 0.0.0.0/0
AWS_OUTPUT[ROUTE_TABLE_ID]=$($AWS ec2 describe-route-tables --filters "Name=vpc-id,Values=${AWS_OUTPUT[VPC_ID]}" --query "RouteTables[0].RouteTableId" --output text || ( console_output "ERROR" "Failed to create route table" && deactivate && exit 1 ))

($AWS ec2 create-route --route-table-id "${AWS_OUTPUT[ROUTE_TABLE_ID]}" --destination-cidr-block 0.0.0.0/0 --gateway-id "${AWS_OUTPUT[IG_ID]}" || ( console_output "ERROR" "Failed to add 0.0.0.0/0" && deactivate && exit 1 ))

# create key pair
($AWS ec2 create-key-pair --key-name "${KEY_PAIR}" --output json --query "KeyMaterial" || ( console_output "ERROR" "Failed to create Key Pair" && deactivate && exit 1 )) | sed -e 's/\\n/\n/g' -e '1!b;s/^"//' -e '$s/"$//' > "${KEY_PAIR_FILE}"
chmod 400 "${KEY_PAIR_FILE}"

# create security group
AWS_OUTPUT[SEC_GRP_ID]=$(($AWS ec2 create-security-group --vpc-id "${AWS_OUTPUT[VPC_ID]}" --group-name "${SEC_GRP}"  --description "${SEC_GRP} for ${AWS_OUTPUT[VPC_ID]}" || ( console_output "ERROR" "Failed to create Secuirty Group" && deactivate && exit 1 )) | awk '{print $1;}')

# add port 22 to the sg
CUR_IP=`curl -s checkip.dyndns.org|sed -e 's/.*Current IP Address: //' -e 's/<.*$//'`/32
($AWS ec2 authorize-security-group-ingress --group-id "${AWS_OUTPUT[SEC_GRP_ID]}" --protocol tcp --port 22 --cidr "${CUR_IP}" || ( console_output "ERROR" "Failed to add port 22" && deactivate && exit 1 ))

# Run an AMI instance
AWS_OUTPUT[INST_ID]=$(($AWS ec2 run-instances --image-id "${AMI_ID}" --count 1 --instance-type t2.micro --subnet-id "${AWS_OUTPUT[SUBNET_ID]}" --associate-public-ip-address --key-name "${KEY_PAIR}" --security-group-ids "${AWS_OUTPUT[SEC_GRP_ID]}" --output json --query "Instances[0].InstanceId" || ( console_output "ERROR" "Failed to run instances" && deactivate && exit 1 )) | sed -e '1!b;s/^"//' -e '$s/"$//')

# deactivate virtualenv
deactivate

exit 0
