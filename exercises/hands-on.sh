#!/usr/bin/env bash

echo "*********************************************************************"
echo "Begin Hands On!"
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
source $TOP_DIR/openrc admin admin

gbp policy-classifier-create http-in --protocol tcp --port-range 80 --direction in --shared True
gbp policy-classifier-create https-in --protocol tcp --port-range 443 --direction in --shared True
gbp policy-classifier-create sql-in --protocol tcp --port-range 3304 --direction in --shared True

gbp policy-rule-create http-in-allow --classifier http-in --actions allow --shared True
gbp policy-rule-create https-in-allow --classifier https-in --actions allow --shared True
gbp policy-rule-create sql-in-allow --classifier sql-in --actions allow --shared True

source $TOP_DIR/openrc demo demo
gbp policy-rule-set-create web --policy-rules 'http-in-allow https-in-allow icmp-bi-allow'
gbp policy-rule-set-create app --policy-rules 'http-in-allow icmp-bi-allow'
gbp policy-rule-set-create db --policy-rules 'sql-in-allow icmp-bi-allow'

gbp group-create web --provided-policy-rule-sets web='' --consumed-policy-rule-sets app='' --network-service-policy vip-ip-policy
gbp group-create app --provided-policy-rule-sets app='' --consumed-policy-rule-sets db='' --network-service-policy vip-ip-policy
gbp group-create db --provided-policy-rule-sets db='' --network-service-policy vip-ip-policy

WEB1_PORT=$(gbp policy-target-create web-pt-1 --policy-target-group web | awk "/port_id/ {print \$4}")
WEB2_PORT=$(gbp policy-target-create web-pt-2 --policy-target-group web | awk "/port_id/ {print \$4}")
APP1_PORT=$(gbp policy-target-create app-pt-1 --policy-target-group app | awk "/port_id/ {print \$4}")
APP2_PORT=$(gbp policy-target-create app-pt-2 --policy-target-group app | awk "/port_id/ {print \$4}")
DB_PORT=$(gbp policy-target-create db-pt-2 --policy-target-group db | awk "/port_id/ {print \$4}")


nova boot --flavor m1.tiny --image cirros-0.3.2-x86_64-uec --nic port-id=$WEB1_PORT web-vm-1
nova boot --flavor m1.tiny --image cirros-0.3.2-x86_64-uec --nic port-id=$WEB2_PORT web-vm-2

nova boot --flavor m1.tiny --image cirros-0.3.2-x86_64-uec --nic port-id=$APP1_PORT app-vm-1
nova boot --flavor m1.tiny --image cirros-0.3.2-x86_64-uec --nic port-id=$APP2_PORT app-vm-2

nova boot --flavor m1.tiny --image cirros-0.3.2-x86_64-uec --nic port-id=$DB_PORT db-vm-1

gbp external-policy-create ext --consumed-policy-rule-sets web=''
