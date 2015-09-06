#!/usr/bin/env bash

## This script is using AWS CLI to provision a EC2 instance post aws cli run-instances

## Require
## AWS CLI - http://aws.amazon.com/cli/

PRJ_ROOT="`cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd`/../../"

. "${PRJ_ROOT}"/lib/shared.func

unset CONF_FILE
unset INTERACTIVE_SHELL
while getopts :c:i option
do
    case "$option" in
        c) CONF_FILE=$OPTARG ;;
        i) INTERACTIVE_SHELL=true ;; # enable interactive shell
        \?) echo "Invalid option: -$OPTARG" >&2 ;; # Invalid options
        :) echo "Option -$OPTARG requires an argument" >&2 ;; # Require an argument
    esac
done
shift $(($OPTIND-1))
[ -z "${CONF_FILE+is_empty_and_null}" ] && echo "Must supply a config file with -c" && exit 1
[ ! -f "${CONF_FILE}" ] && echo "${CONF_FILE} is not a regular file" && exit 1

. "${PRJ_ROOT}"/lib/aws.func # AWS setup
. "${PRJ_ROOT}"/lib/folder.func # @ $_WORK_DIR

## Define variables
PIP=`which pip`
#VIRTUALENV="$_WORK_DIR_"/virenv
VIRTUALENV=~/virenv

# install virtualenv
$PIP install --upgrade --user virtualenv -q || { console_output "ERROR" "Failed to install virtuallenv using pip, existing" && deactivate && exit 1 ; }

# create a virtualenv
mkdir -p "${VIRTUALENV}"
~/.local/bin/virtualenv $VIRTUALENV -q
. $VIRTUALENV/bin/activate # inside virtualenv

# parameters inside virtualenv
AWS="`which python` "${VIRTUALENV}"/bin/aws"
AWS_CONF=`dirname "${CONF_FILE}"`/`grep conf_file ${CONF_FILE} | sed -e 's/^.*=\(.*\)$/\1/'` # get aws config
export AWS_CONFIG_FILE="${AWS_CONF}" # load the aws config file
INS_ID=`grep instance_id ${CONF_FILE} | sed -e 's/^.*=\(.*\)$/\1/'` # get the instance id

# update security group
SEC_GRP_ID=`grep security_group_id ${CONF_FILE} | sed -e 's/^.*=\(.*\)$/\1/'`
OLD_IP=$($AWS ec2 describe-security-groups --group-id "${SEC_GRP_ID}" --filters "Name=ip-permission.from-port,Values=22" --query "SecurityGroups[*].IpPermissions[*].IpRanges[*].CidrIp")
$AWS ec2 revoke-security-group-ingress --group-id "${SEC_GRP_ID}" --protocol tcp --port 22 --cidr "${OLD_IP}" || { console_output "ERROR" "Failed to remove port 22" && deactivate && exit 1 ; }
CUR_IP=`curl -s checkip.dyndns.org|sed -e 's/.*Current IP Address: //' -e 's/<.*$//'`/32
$AWS ec2 authorize-security-group-ingress --group-id "${SEC_GRP_ID}" --protocol tcp --port 22 --cidr "${CUR_IP}" || { console_output "ERROR" "Failed to add port 22" && deactivate && exit 1 ; }

# start ami
while true
do
    # check if the instance is running
    INS_STAT=$($AWS ec2 describe-instances --instance-id "${INS_ID}" --query "Reservations[*].Instances[*].State.Code" || { console_output "ERROR" "Failed to get status for the instance ${INS_ID}, existing" && deactivate && exit 1 ; })
    [ `is_empty ${INS_STAT}`  == true ] && { console_output "ERROR" "Instance ${INS_ID} does nto exist, existing" && deactivate && exit 1 ; }

    case "${INS_STAT}" in
        0 | 32 | 64) sleep 5 ;; # pending/shutting-down/stopping
        16) break ;; # running
        48) { console_output "ERROR" "Instance ${INS_ID} is terminated, existing" && deactivate && exit 1 ; } ;;
        80) $AWS ec2 start-instances --instance-id "${INS_ID}" || { console_output "ERROR" "Failed to start Instance ${INS_ID}, existing" && deactivate && exit 1 ; } ;;
        *) { console_output "ERROR" "Unknown instance status for ${INS_ID}, existing" && deactivate && exit 1 ; } ;;
    esac
done

# run commands on the remote instance
SSH_HOST="ec2-user@$($AWS ec2 describe-instances --instance-id "${INS_ID}" --query "Reservations[*].Instances[*].PublicIpAddress" || { console_output "ERROR" "Failed to start Instance ${INS_ID}, existing" && deactivate && exit 1 ; })"
SSH_KEY="-i `dirname ${CONF_FILE}`/`grep key_pair_file ${CONF_FILE} | sed -e 's/^.*=\(.*\)$/\1/'`"
SSH_OPT="-o ConnectTimeout=30 -o StrictHostKeyChecking=no -o LogLevel=ERROR -o UserKnownHostsFile=/dev/null `# FIXME - security enhancement` -t"
SSH_RUN="`which ssh` ${SSH_KEY} ${SSH_OPT} ${SSH_HOST}"

# logon setup
LOGON=$(cat <<EOF
EOF
)
if [ ! -z "${LOGON// }" ]; then
    $SSH_RUN 'bash -s ' <<EOF
# run before interactive logon
echo "#############################################"
echo "Executing commands inside instance ${INS_ID}"
echo "#############################################"
eval "${LOGON}"
EOF
fi

# interactive shell
if [ "${INTERACTIVE_SHELL}" == true ] ; then ${SSH_RUN} ; fi

# logoff clean up
LOGOFF=$(cat <<EOF
EOF
)
if [ ! -z "${LOGOFF// }" ]; then
    $SSH_RUN 'bash -s ' <<EOF
# run when log off the ssh session
eval "${LOGOFF}"
EOF
fi

# deactivate virtualenv
deactivate

exit 0
