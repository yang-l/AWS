#!/usr/bin/env bash

## This script is using AWS CLI to create a EC2 instance

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
BUILD_NAME="EC2_BUILD_`date +"%F_%H-%M-%S_%Z"`"
BUILD_CONF="${VIRTUALENV}/${BUILD_NAME}"
BUILD_RCRD="${BUILD_CONF}/build.info"

# install virtualenv
$PIP install --upgrade --user virtualenv -q || { console_output "ERROR" "Failed to install virtuallenv using pip, existing" && exit 1 ; }

# create a virtualenv
mkdir -p "${BUILD_CONF}"
~/.local/bin/virtualenv $VIRTUALENV -q
. $VIRTUALENV/bin/activate # inside virtualenv

# parameters
AMI_ID="ami-1ecae776"
AWS="`which python` "${VIRTUALENV}"/bin/aws"
KEY_PAIR="${BUILD_NAME}_Key_Pair"
KEY_PAIR_FILE="${BUILD_CONF}/${KEY_PAIR}.pem"
SEC_GRP="${BUILD_NAME}_SEC_GRP"
SUBNET="192.168.10.1/28"

# store output ids
declare -A AWS_OUTPUT # store AWS output IDs

# create configuration file and export
cat <<EOF >  "${BUILD_CONF}/aws.cfg"
[default]
region = us-east-1
output = text
EOF
export AWS_CONFIG_FILE="${BUILD_CONF}/aws.cfg" # override default location
echo "conf_file=./aws.cfg" > "${BUILD_RCRD}"

# install awscli in virtualenv
pip install --upgrade awscli -q || { console_output "ERROR" "Failed to install awscli via pip in virtualenv, existing" && deactivate && exit 1 ; }

# create VPC
AWS_OUTPUT[VPC_ID]=$(($AWS ec2 create-vpc --cidr-block "${SUBNET}" || { console_output "ERROR" "Failed to create VPC" && deactivate && exit 1 ; }) | awk '{print $6;}')
echo "vpc_id=${AWS_OUTPUT[VPC_ID]}" >> "${BUILD_RCRD}"

# create internet gateway
AWS_OUTPUT[IG_ID]=$(($AWS ec2 create-internet-gateway || { console_output "ERROR" "Failed to create Internet Gateway" && deactivate && exit 1 ; }) | awk '{print $2}')
echo "internet_gateway_id=${AWS_OUTPUT[IG_ID]}" >> "${BUILD_RCRD}"

# attach IG to VPC
($AWS ec2 attach-internet-gateway --internet-gateway-id "${AWS_OUTPUT[IG_ID]}" --vpc-id "${AWS_OUTPUT[VPC_ID]}"  || { console_output "ERROR" "Failed to attach IG (${AWS_OUTPUT[IG_ID]}) to VPC (${AWS_OUTPUT[VPC_ID]})" && deactivate && exit 1 ; })

# create subnet
AWS_OUTPUT[SUBNET_ID]=$(($AWS ec2 create-subnet --vpc-id ${AWS_OUTPUT[VPC_ID]} --cidr-block "${SUBNET}" || { console_output "ERROR" "Failed to create SUBNET" && deactivate && exit 1 ; }) | awk '{print $6;}')

# add 0.0.0.0/0
AWS_OUTPUT[ROUTE_TABLE_ID]=$($AWS ec2 describe-route-tables --filters "Name=vpc-id,Values=${AWS_OUTPUT[VPC_ID]}" --query "RouteTables[0].RouteTableId" --output text || { console_output "ERROR" "Failed to create route table" && deactivate && exit 1 ; })
echo "route_table_id=${AWS_OUTPUT[ROUTE_TABLE_ID]}" >> "${BUILD_RCRD}"

($AWS ec2 create-route --route-table-id "${AWS_OUTPUT[ROUTE_TABLE_ID]}" --destination-cidr-block 0.0.0.0/0 --gateway-id "${AWS_OUTPUT[IG_ID]}" || { console_output "ERROR" "Failed to add 0.0.0.0/0" && deactivate && exit 1 ; })

# create key pair
($AWS ec2 create-key-pair --key-name "${KEY_PAIR}" --output json --query "KeyMaterial" || { console_output "ERROR" "Failed to create Key Pair" && deactivate && exit 1 ; }) | sed -e 's/\\n/\n/g' -e '1!b;s/^"//' -e '$s/"$//' > "${KEY_PAIR_FILE}"
chmod 400 "${KEY_PAIR_FILE}"
echo "key_pair_file=./${KEY_PAIR}.pem" >> "${BUILD_RCRD}"

# create security group
AWS_OUTPUT[SEC_GRP_ID]=$(($AWS ec2 create-security-group --vpc-id "${AWS_OUTPUT[VPC_ID]}" --group-name "${SEC_GRP}"  --description "${SEC_GRP} for ${AWS_OUTPUT[VPC_ID]}" || { console_output "ERROR" "Failed to create Secuirty Group" && deactivate && exit 1 ; }) | awk '{print $1;}')
echo "security_group_id=${AWS_OUTPUT[SEC_GRP_ID]}" >> "${BUILD_RCRD}"

# add port 22 to the sg
CUR_IP=`curl -s checkip.dyndns.org|sed -e 's/.*Current IP Address: //' -e 's/<.*$//'`/32
$AWS ec2 authorize-security-group-ingress --group-id "${AWS_OUTPUT[SEC_GRP_ID]}" --protocol tcp --port 22 --cidr "${CUR_IP}" || { console_output "ERROR" "Failed to add port 22" && deactivate && exit 1 ; }

# Run an AMI instance
PROV_SETUP=$(cat <<EOF
#!/usr/bin/env bash
# logged in and run as the root user

# upgrade pip (when necessary)
echo "Upgrade pip ... (root)"
pip install --upgrade pip || echo "Failed to upgrade pip"

# upgrade virtualenv
echo "Install virtualenv ... (root)"
/usr/local/bin/pip install --upgrade virtualenv || echo "Failed to install virtuallenv via pip"

# install packer
echo "Install Packer ..."
cd /usr/local/
wget https://dl.bintray.com/mitchellh/packer/packer_0.8.6_linux_amd64.zip -O ./packer.zip
unzip ./packer.zip -d ./bin
rm ./packer.zip

exit 0
EOF
) # end of $PROV_SETUP

AWS_OUTPUT[INST_ID]=$(($AWS ec2 run-instances --image-id "${AMI_ID}" --count 1 --instance-type t2.micro --subnet-id "${AWS_OUTPUT[SUBNET_ID]}" --associate-public-ip-address --key-name "${KEY_PAIR}" --security-group-ids "${AWS_OUTPUT[SEC_GRP_ID]}" --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"DeleteOnTermination\":true,\"SnapshotId\":\"snap-b772aec8\",\"VolumeSize\":8,\"VolumeType\":\"gp2`#standard`\"}}]" --user-data "${PROV_SETUP}" --output json --query "Instances[0].InstanceId" || { console_output "ERROR" "Failed to run instances" && deactivate && exit 1 ; }) | sed -e '1!b;s/^"//' -e '$s/"$//')
echo "instance_id=${AWS_OUTPUT[INST_ID]}" >> "${BUILD_RCRD}"

# copy config files to S3
if [ `$AWS s3 ls | grep -i "${INST_S3PATH}" | wc -l` == 0 ] ; then $AWS s3 mb s3://"${INST_S3PATH}" ; fi # check S3 bucket
$AWS s3 mv "${BUILD_CONF}" s3://"${INST_S3PATH}"/"${AWS_OUTPUT[INST_ID]}" --recursive --sse --no-guess-mime-type --only-show-errors
rmdir "${BUILD_CONF}"

# deactivate virtualenv
deactivate

exit 0
