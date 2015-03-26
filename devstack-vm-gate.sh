#!/bin/bash

# Script that is run on the devstack vm; configures and
# invokes devstack.

# Copyright (C) 2011-2012 OpenStack LLC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
#
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit

# Keep track of the devstack directory
TOP_DIR=$(cd $(dirname "$0") && pwd)

# Prepare the environment
# -----------------------

# Import common functions
source $TOP_DIR/functions.sh

echo $PPID > $WORKSPACE/gate.pid
source `dirname "$(readlink -f "$0")"`/functions.sh

FIXED_RANGE=${DEVSTACK_GATE_FIXED_RANGE:-10.1.0.0/20}
FLOATING_RANGE=${DEVSTACK_GATE_FLOATING_RANGE:-172.24.5.0/24}
PUBLIC_NETWORK_GATEWAY=${DEVSTACK_GATE_PUBLIC_NETWORK_GATEWAY:-172.24.5.1}
# The next two values are used in multinode testing and are related
# to the floating range. For multinode test envs to know how to route
# packets to floating IPs on other hosts we put addresses on the compute
# node interfaces on a network that overlaps the FLOATING_RANGE. This
# automagically sets up routing in a sane way. By default we put floating
# IPs on 172.24.5.0/24 and compute nodes get addresses in the 172.24.4/23
# space. Note that while the FLOATING_RANGE should overlap the
# FLOATING_HOST_* space you should have enough sequential room starting at
# the beginning of your FLOATING_HOST range to give one IP address to each
# compute host without letting compute host IPs run into the FLOATING_RANGE.
# By default this lets us have 255 compute hosts (172.24.4.1 - 172.24.4.255).
FLOATING_HOST_PREFIX=${DEVSTACK_GATE_FLOATING_HOST_PREFIX:-172.24.4}
FLOATING_HOST_MASK=${DEVSTACK_GATE_FLOATING_HOST_MASK:-23}

if [[ -n "$DEVSTACK_GATE_GRENADE" ]]; then
    echo "Not supported"

else
    cd $BASE/new/devstack

    if [[ "$DEVSTACK_GATE_TOPOLOGY" != "aio" ]]; then
        set -x  # for now enabling debug and do not turn it off
        sudo mkdir -p $BASE/new/.ssh
        sudo cp /etc/nodepool/id_rsa.pub $BASE/new/.ssh/authorized_keys
        sudo cp /etc/nodepool/id_rsa $BASE/new/.ssh/
        sudo chmod 600 $BASE/new/.ssh/authorized_keys
        sudo chmod 400 $BASE/new/.ssh/id_rsa
        for NODE in `cat /etc/nodepool/sub_nodes_private`; do
            echo "Copy Files to  $NODE"
            remote_copy_dir $NODE $BASE/new/devstack-gate $WORKSPACE
            remote_copy_file $WORKSPACE/test_env.sh $NODE:$WORKSPACE/test_env.sh
            echo "Preparing $NODE"
            remote_command $NODE "source $WORKSPACE/test_env.sh; $WORKSPACE/devstack-gate/sub_node_prepare.sh"
            remote_copy_file /etc/nodepool/id_rsa "$NODE:$BASE/new/.ssh/"
            remote_command $NODE sudo chmod 400 "$BASE/new/.ssh/*"
        done
        PRIMARY_NODE=`cat /etc/nodepool/primary_node_private`
        SUB_NODES=`cat /etc/nodepool/sub_nodes_private`
        NODES="$PRIMARY_NODE $SUB_NODES"
        if [[ "$DEVSTACK_GATE_NEUTRON" -ne '1' ]]; then
            (source $BASE/new/devstack/functions-common; install_package bridge-utils)
            gre_bridge "flat_if" "pub_if" 1 $FLOATING_HOST_PREFIX $FLOATING_HOST_MASK $NODES
            cat <<EOF >>"$BASE/new/devstack/sub_localrc"
FLAT_INTERFACE=flat_if
PUBLIC_INTERFACE=pub_if
MULTI_HOST=True
EOF
            cat <<EOF >>"$BASE/new/devstack/localrc"
FLAT_INTERFACE=flat_if
PUBLIC_INTERFACE=pub_if
MULTI_HOST=True
EOF
        fi
    fi
    # Make the workspace owned by the stack user
    sudo chown -R stack:stack $BASE

    echo "Running devstack"
    echo "... this takes 5 - 8 minutes (logs in logs/devstacklog.txt.gz)"
    start=$(date +%s)
    sudo -H -u stack stdbuf -oL -eL ./stack.sh > /dev/null
    end=$(date +%s)
    took=$((($end - $start) / 60))
    if [[ "$took" -gt 15 ]]; then
        echo "WARNING: devstack run took > 15 minutes, this is a very slow node."
    fi

    # provide a check that the right db was running
    # the path are different for fedora and red hat.
    if [[ -f /usr/bin/yum ]]; then
        POSTGRES_LOG_PATH="-d /var/lib/pgsql"
        MYSQL_LOG_PATH="-f /var/log/mysqld.log"
    else
        POSTGRES_LOG_PATH="-d /var/log/postgresql"
        MYSQL_LOG_PATH="-d /var/log/mysql"
    fi
    if [[ "$DEVSTACK_GATE_POSTGRES" -eq "1" ]]; then
        if [[ ! $POSTGRES_LOG_PATH ]]; then
            echo "Postgresql should have been used, but there are no logs"
            exit 1
        fi
    else
        if [[ ! $MYSQL_LOG_PATH ]]; then
            echo "Mysql should have been used, but there are no logs"
            exit 1
        fi
    fi

    if [[ "$DEVSTACK_GATE_TOPOLOGY" != "aio" ]]; then
        echo "Preparing cross node connectivity"
        # set up ssh_known_hosts by IP and /etc/hosts
        for NODE in `cat /etc/nodepool/sub_nodes_private`; do
            ssh-keyscan $NODE | sudo tee --append tmp_ssh_known_hosts > /dev/null
            echo $NODE `remote_command $NODE hostname -f | tr -d '\r'` | sudo tee --append  tmp_hosts > /dev/null
        done
        ssh-keyscan `cat /etc/nodepool/primary_node_private` | sudo tee --append tmp_ssh_known_hosts > /dev/null
        echo `cat /etc/nodepool/primary_node_private` `hostname -f` | sudo tee --append tmp_hosts > /dev/null
        cat tmp_hosts | sudo tee --append /etc/hosts

        # set up ssh_known_host files based on hostname
        for HOSTNAME in `cat tmp_hosts | cut -d' ' -f2`; do
            ssh-keyscan $HOSTNAME | sudo tee --append tmp_ssh_known_hosts > /dev/null
        done
        sudo cp tmp_ssh_known_hosts /etc/ssh/ssh_known_hosts
        sudo chmod 444 /etc/ssh/ssh_known_hosts

        for NODE in `cat /etc/nodepool/sub_nodes_private`; do
            remote_copy_file tmp_ssh_known_hosts $NODE:$BASE/new/tmp_ssh_known_hosts
            remote_copy_file tmp_hosts $NODE:$BASE/new/tmp_hosts
            remote_command $NODE "cat $BASE/new/tmp_hosts | sudo tee --append /etc/hosts > /dev/null"
            remote_command $NODE "sudo mv $BASE/new/tmp_ssh_known_hosts /etc/ssh/ssh_known_hosts"
            remote_command $NODE "sudo chmod 444 /etc/ssh/ssh_known_hosts"
            sudo cp sub_localrc tmp_sub_localrc
            echo "HOST_IP=$NODE" | sudo tee --append tmp_sub_localrc > /dev/null
            remote_copy_file tmp_sub_localrc $NODE:$BASE/new/devstack/localrc
            remote_command $NODE sudo chown -R stack:stack $BASE
            echo "Running devstack on $NODE"
            remote_command $NODE "cd $BASE/new/devstack; source $WORKSPACE/test_env.sh; export -n PROJECTS; sudo -H -u stack stdbuf -oL -eL ./stack.sh > /dev/null"
        done

       if [[ $DEVSTACK_GATE_NEUTRON -eq "1" ]]; then
            # NOTE(afazekas): The cirros lp#1301958 does not support MTU setting via dhcp,
            # simplest way the have tunneling working, with dvsm, without increasing the host system MTU
            # is to decreasion the MTU on br-ex
            # TODO(afazekas): Configure the mtu smarter on the devstack side
            sudo ip link set mtu 1450 dev br-ex
        fi
    fi
fi

if [[ "$DEVSTACK_GATE_UNSTACK" -eq "1" ]]; then
   sudo -H -u stack ./unstack.sh
fi

echo "Removing sudo privileges for devstack user"
sudo rm /etc/sudoers.d/50_stack_sh

if [[ "$DEVSTACK_GATE_EXERCISES" -eq "1" ]]; then
    echo "Running devstack exercises"
    sudo -H -u stack ./exercise.sh
fi

function load_subunit_stream {
    local stream=$1;
    pushd /opt/stack/new/tempest/
    sudo testr load --force-init $stream
    popd
}


if [[ "$DEVSTACK_GATE_TEMPEST" -eq "1" ]]; then
    #TODO(mtreinish): This if block can be removed after all the nodepool images
    # are built using with streams dir instead
    echo "Loading previous tempest runs subunit streams into testr"
    if [[ -f /opt/git/openstack/tempest/.testrepository/0 ]]; then
        temp_stream=`mktemp`
        subunit-1to2 /opt/git/openstack/tempest/.testrepository/0 > $temp_stream
        load_subunit_stream $temp_stream
    elif [[ -d /opt/git/openstack/tempest/preseed-streams ]]; then
        for stream in /opt/git/openstack/tempest/preseed-streams/* ; do
            load_subunit_stream $stream
        done
    fi

    # under tempest isolation tempest will need to write .tox dir, log files
    if [[ -d "$BASE/new/tempest" ]]; then
        sudo chown -R tempest:stack $BASE/new/tempest
    fi
    # Make sure tempest user can write to its directory for
    # lock-files.
    if [[ -d $BASE/data/tempest ]]; then
        sudo chown -R tempest:stack $BASE/data/tempest
    fi
    # ensure the cirros image files are accessible
    if [[ -d /opt/stack/new/devstack/files ]]; then
        sudo chmod -R o+rx /opt/stack/new/devstack/files
    fi

    # if set, we don't need to run Tempest at all
    if [[ "$DEVSTACK_GATE_TEMPEST_NOTESTS" -eq "1" ]]; then
        exit 0
    fi

    # From here until the end we rely on the fact that all the code fails if
    # something is wrong, to enforce exit on bad test results.
    set -o errexit

    cd $BASE/new/tempest
    if [[ "$DEVSTACK_GATE_TEMPEST_REGEX" != "" ]] ; then
        echo "Running tempest with a custom regex filter"
        sudo -H -u tempest tox -eall -- --concurrency=$TEMPEST_CONCURRENCY $DEVSTACK_GATE_TEMPEST_REGEX
    elif [[ "$DEVSTACK_GATE_TEMPEST_ALL" -eq "1" ]]; then
        echo "Running tempest all test suite"
        sudo -H -u tempest tox -eall -- --concurrency=$TEMPEST_CONCURRENCY
    elif [[ "$DEVSTACK_GATE_TEMPEST_DISABLE_TENANT_ISOLATION" -eq "1" ]]; then
        echo "Running tempest full test suite serially"
        sudo -H -u tempest tox -efull-serial
    elif [[ "$DEVSTACK_GATE_TEMPEST_FULL" -eq "1" ]]; then
        echo "Running tempest full test suite"
        sudo -H -u tempest tox -efull -- --concurrency=$TEMPEST_CONCURRENCY
    elif [[ "$DEVSTACK_GATE_TEMPEST_STRESS" -eq "1" ]] ; then
        echo "Running stress tests"
        sudo -H -u tempest tox -estress -- $DEVSTACK_GATE_TEMPEST_STRESS_ARGS
    elif [[ "$DEVSTACK_GATE_TEMPEST_HEAT_SLOW" -eq "1" ]] ; then
        echo "Running slow heat tests"
        sudo -H -u tempest tox -eheat-slow -- --concurrency=$TEMPEST_CONCURRENCY
    elif [[ "$DEVSTACK_GATE_TEMPEST_LARGE_OPS" -ge "1" ]] ; then
        echo "Running large ops tests"
        sudo -H -u tempest tox -elarge-ops -- --concurrency=$TEMPEST_CONCURRENCY
    elif [[ "$DEVSTACK_GATE_SMOKE_SERIAL" -eq "1" ]] ; then
        echo "Running tempest smoke tests"
        sudo -H -u tempest tox -esmoke-serial
    else
        echo "Running tempest smoke tests"
        sudo -H -u tempest tox -esmoke -- --concurrency=$TEMPEST_CONCURRENCY
    fi

fi
