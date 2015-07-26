#!/usr/bin/env bash

## This script is using AWS CLI to create a EC2 instance

## Require
## AWS CLI - http://aws.amazon.com/cli/

. `cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd`/../../lib/shared.func
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

# install awscli in virtualenv
pip install --upgrade awscli -q || ( console_output "ERROR" "Failed to install awscli using pip in virtualenv, existing" && deactivate && exit 1 )

## TODO - ec2-create-imageec2-create-image to create EC2 instance

# deactivate virtualenv
deactivate
