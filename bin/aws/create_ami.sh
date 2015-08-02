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
. $VIRTUALENV/bin/activate

AWS="`which python` "${VIRTUALENV}"/bin/aws"

# create configuration files
#export AWS_CONFIG_FILE="$VIRTUALENV/aws.cfg" # override default location

# install awscli in virtualenv
pip install --upgrade awscli -q || ( console_output "ERROR" "Failed to install awscli using pip in virtualenv, existing" && deactivate && exit 1 )

$AWS ec2 create-image --instance-id i-2bc338f9 --name "Clone AMI" --description "An AMI for build automation"

# deactivate virtualenv
deactivate
