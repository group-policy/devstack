# odlgbp.sh - DevStack extras script

if is_service_enabled odlgbp; then
    # Initial source
    if [[ "$1" == "source" ]]; then
        # no-op
        :
    elif [[ "$1" == "stack" && "$2" == "install" ]]; then
        #install_opendaylight-compute
        # no-op
        :
    elif [[ "$1" == "stack" && "$2" == "post-config" ]]; then
        #if is_service_enabled nova; then
        #    create_nova_conf_neutron
        #fi
        # no-op
        :
    elif [[ "$1" == "stack" && "$2" == "extra" ]]; then
        sudo ovs-vsctl --no-wait add-br br-int
        sudo ovs-vsctl --no-wait br-set-external-id br-int bridge-id br-int
        sudo ovs-vsctl set bridge br-int protocols=OpenFlow13
        sudo ovs-vsctl set-controller br-int tcp:$ODL_MGR_IP:$ODL_MGR_PORT
        if is_service_enabled q-l3; then
            sudo ovs-vsctl set bridge br-ex protocols=OpenFlow13
            sudo ovs-vsctl set-controller br-ex tcp:$ODL_MGR_IP:$ODL_MGR_PORT
        fi

    elif [[ "$1" == "stack" && "$2" == "post-extra" ]]; then
        # no-op
        :
    fi

    if [[ "$1" == "unstack" ]]; then
        # no-op
        :
    fi


    if [[ "$1" == "clean" ]]; then
        # no-op
        :
    fi
fi

