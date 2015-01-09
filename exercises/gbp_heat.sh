#!/usr/bin/env bash

# **gbp_heat.sh**

# Sanity check that gbp and gbp heat plugin works fine if enabled

echo "*********************************************************************"
echo "Begin DevStack Exercise: $0"
echo "*********************************************************************"

# This script exits on an error so that errors don't compound and you see
# only the first error that occurred.
set -o errexit

# Print the commands being run so that we can see the command that triggers
# an error.  It is also useful for following redirecting as the install occurs.
set -o xtrace

STACK_CREATE_TIMEOUT=300
STACK_DELETE_TIMEOUT=120
STACK_NAME=gbp_test_template

# Settings
# ========

# Keep track of the current directory
EXERCISE_DIR=$(cd $(dirname "$0") && pwd)
TOP_DIR=$(cd $EXERCISE_DIR/..; pwd)

# Import common functions
source $TOP_DIR/functions

# Import configuration
source $TOP_DIR/openrc

# Import exercise configuration
source $TOP_DIR/exerciserc

source $TOP_DIR/openrc demo demo

function confirm_stack_active {
    local STACK_NAME=$1
    if ! timeout $STACK_CREATE_TIMEOUT sh -c "while ! heat stack-show $STACK_NAME | grep status | grep -q CREATE_COMPLETE; do sleep 1; done"; then
        echo "server '$STACK_NAME' did not become active!"
        false
    fi
}

STACK_UUID=`heat stack-create -f gbp-templates/firewall-lb-servicechain/demo.yaml $STACK_NAME | grep $STACK_NAME | cut -d"|" -f2 | sed 's/ //g'`

die_if_not_set $LINENO $STACK_UUID "Failure launching gbp stack"
confirm_stack_active $STACK_NAME


heat stack-delete $STACK_NAME


if ! timeout $STACK_DELETE_TIMEOUT sh -c "while heat stack-list | grep -q $STACK_NAME; do sleep 1; done"; then
    die $LINENO "Stack failed to delete"
fi


set +o xtrace
echo "*********************************************************************"
echo "SUCCESS: End DevStack Exercise: $0"
echo "*********************************************************************"
