#!/usr/bin/env bash

## This script is using AWS CLI to clean up AWS EC2/ESB/VPC/...

## Require
## AWS CLI - http://aws.amazon.com/cli/

# $1 - AWS parameter override file

PRJ_ROOT="`cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd`/../../"

. "${PRJ_ROOT}"/lib/shared.func
. "${PRJ_ROOT}"/lib/aws.func $1 # AWS setup
. "${PRJ_ROOT}"/lib/folder.func # @ $_WORK_DIR

## Define variables
PIP=`which pip`
#VIRTUALENV="$_WORK_DIR_"/virenv
VIRTUALENV=~/virenv

# install virtualenv
$PIP install --upgrade --user virtualenv -q || { console_output "ERROR" "Failed to install virtuallenv using pip, existing" && exit 1 ; }

# create a virtualenv
mkdir -p "$VIRTUALENV"
~/.local/bin/virtualenv $VIRTUALENV -q
. $VIRTUALENV/bin/activate # inside virtualenv

# parameters
AWS="`which python` "${VIRTUALENV}"/bin/aws"

# create configuration file and export
cat <<EOF >  "$VIRTUALENV/aws.cfg"
[default]
region = us-east-1
output = text
EOF
export AWS_CONFIG_FILE="$VIRTUALENV/aws.cfg" # override default location

console_output "INFO" "Terminate ALL instances:"
for I in `($AWS ec2 describe-instances --query "Reservations[*].Instances[*].InstanceId" || { console_output "ERROR" "Failed to list instances" && deactivate && exit 1 ; }) | uniq`;
do
    echo "Terminate ${I}"
    $AWS ec2 terminate-instances --instance-ids "${I}" || { console_output "ERROR" "Failed to terminate the instance" && deactivate && exit 1 ; }
done

console_output "INFO" "Check ALL instances are terminated:"
for I in `($AWS ec2 describe-instances --query "Reservations[*].Instances[*].InstanceId" || { console_output "ERROR" "Failed to list instances" && deactivate && exit 1 ; }) | uniq`;
do
    while true; do
        echo "Check ${I}"
        STOP=$($AWS ec2 describe-instances --instance-id "${I}" --query "Reservations[*].Instances[*].State.Code")
        if [ "${STOP}" == 48 ]; then break; fi
        sleep 5
    done
done

console_output "INFO" "Remove ALL subnets:"
for SN in `($AWS ec2 describe-subnets --query "Subnets[*].SubnetId" || { console_output "ERROR" "Failed to list subnets" && deactivate && exit 1 ; }) | uniq`;
do
    echo "Delete ${SN}"
    $AWS ec2 delete-subnet --subnet-id "${SN}" || { console_output "ERROR" "Failed to delete the subnet" && deactivate && exit 1 ; }
done

console_output "INFO" "Remove ALL security groups:"
for SG in `($AWS ec2 describe-security-groups --query "SecurityGroups[*].GroupId" || { console_output "ERROR" "Failed to list SGs" && deactivate && exit 1 ; }) | uniq`;
do
    SG_DEF=$($AWS ec2 describe-security-groups --filters "Name=group-id,Values=${SG}" --query "SecurityGroups[*].GroupName")

    [ $SG_DEF == "default" ] && continue
    echo "Delete ${SG}"
    $AWS ec2 delete-security-group --group-id "${SG}" || { console_output "ERROR" "Failed to delete the SG" && deactivate && exit 1 ; }
done

console_output "INFO" "Remove ALL internet gateways:"
for IG in `($AWS ec2 describe-internet-gateways --query "InternetGateways[*].InternetGatewayId" || { console_output "ERROR" "Failed to list IGs" && deactivate && exit 1 ; }) | uniq`;
do
    echo "Delete ${IG}"
    VPC_ID=$($AWS ec2 describe-internet-gateways --filters "Name=internet-gateway-id,Values=${IG}" --query "InternetGateways[*].Attachments[*].VpcId")
    [ `is_empty "${VPC_ID}"` == false ] && ($AWS ec2 detach-internet-gateway --internet-gateway-id "${IG}" --vpc-id "${VPC_ID}" || { console_output "ERROR" "Failed to detech the route table" && deactivate && exit 1 ; })
    $AWS ec2 delete-internet-gateway --internet-gateway-id "${IG}" || { console_output "ERROR" "Failed to delete the route table" && deactivate && exit 1 ; }
done

console_output "INFO" "Remove ALL VPCs:"
for V in `($AWS ec2 describe-vpcs --query "Vpcs[*].VpcId" || { console_output "ERROR" "Failed to list VPCs" && deactivate && exit 1 ; }) | uniq`;
do
    echo "Delete ${V}"
    $AWS ec2 delete-vpc --vpc-id "${V}" || { console_output "ERROR" "Failed to delete the VPC" && deactivate && exit 1 ; }
done

console_output "INFO" "Remove ALL route tables:"
for RT in `($AWS ec2 describe-route-tables --query "RouteTables[*].RouteTableId" || { console_output "ERROR" "Failed to list VPCs" && deactivate && exit 1 ; }) | uniq`;
do
    echo "Delete ${RT}"
    $AWS ec2 delete-route-table --route-table-id "${RT}" || { console_output "ERROR" "Failed to delete the route table" && deactivate && exit 1 ; }
done

console_output "INFO" "Remove ALL network ACLs:"
for NA in `($AWS ec2 describe-network-acls --query "NetworkAcls[*].NetworkAclId" || { console_output "ERROR" "Failed to list network ACLs" && deactivate && exit 1 ; }) | uniq`;
do
    echo "Delete ${NA}"
    $AWS ec2 delete-network-acl --network-acl-id "${NA}" || { console_output "ERROR" "Failed to delete the network ACL" && deactivate && exit 1 ; }
done

console_output "INFO" "Remove ALL key pairs:"
for K in `($AWS ec2 describe-key-pairs --query "KeyPairs[*].KeyName" || { console_output "ERROR" "Failed to list key pairs" && deactivate && exit 1 ; }) | uniq`;
do
    echo "Delete ${K}"
    $AWS ec2 delete-key-pair --key-name "${K}" || { console_output "ERROR" "Failed to delete the key pair" && deactivate && exit 1 ; }
done

# clean up local files
console_output "INFO" "Remove ALL local config files:"
rm "${VIRTUALENV}/aws.cfg"

# remove S3 backet
console_output "INFO" "Remove ALL config files in S3:"
if [ `$AWS s3 ls | grep -i "${INST_S3PATH}" | wc -l` != 0 ] ; then $AWS s3 rb s3://"${INST_S3PATH}" --force ; fi # check & removeS3 bucket

# deactivate virtualenv
deactivate

exit 0
