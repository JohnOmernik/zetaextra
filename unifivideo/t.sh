#!/bin/bash

SRV="/home/zetaadm/homecluster/zetago/conf/firewall/services.conf"



PORTS="7448 7445 7446 7447 7080 6666"


for P in $PORTS; do
    CHK=$(grep ":$P:" $SRV)
    if [ "$CHK" == "" ]; then
        echo "$P Not found we are good"
    else
        echo "$P found we have issues"
    fi
done
