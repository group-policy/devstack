#!/usr/bin/env bash

echo "*********************************************************************"
echo "Begin Hands Off!"
echo "*********************************************************************"

# Keep track of the current directory
EXERCISE_DIR=$(cd $(dirname "$0") && pwd)
TOP_DIR=$(cd $EXERCISE_DIR/..; pwd)

# Import common functions
source $TOP_DIR/functions

# Import configuration
source $TOP_DIR/openrc

# Import exercise configuration
source $TOP_DIR/exerciserc

# Admin Ops
source $TOP_DIR/openrc demo demo

gbp external-policy-delete ext

nova delete web-vm-1
nova delete web-vm-2
nova delete app-vm-1
nova delete app-vm-2
nova delete db-vm-1

gbp group-delete web
gbp group-delete app
gbp group-delete db

gbp policy-rule-set-delete web
gbp policy-rule-set-delete app
gbp policy-rule-set-delete db

source $TOP_DIR/openrc admin admin

gbp policy-rule-delete http-in-allow
gbp policy-rule-delete https-in-allow
gbp policy-rule-delete sql-in-allow

gbp policy-classifier-delete http-in
gbp policy-classifier-delete https-in
gbp policy-classifier-delete sql-in
