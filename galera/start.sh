#!/bin/bash

BOOT_CHK=$(cat $APP_HOME/creds/boot.txt)
NODES=$(ls -1 $APP_HOME|grep "node")
BOOT_NODE="node1"

if [ "$BOOT_CHK" == "0" ]; then

    # Need to initialize the Boot node!
    @go.log WARN "Since this is the initial Run of the bootstrap node, we are going to start it with the create cluster flag"
    MAR_FILE="$APP_HOME/$BOOT_NODE/marathon.json"
    MAR_ID="${APP_ROLE}/${APP_ID}/node1"
    submitstartsvc "RES" "$MAR_ID" "$MAR_FILE" "$MARATHON_SUBMIT"
    if [ "$RES" != "0" ]; then
        @go.log WARN "$MAR_ID not started - is it already running?"
    fi
    echo ""
    echo "Waiting 30 Seconds"
    sleep 30

    CURHOST=$(./zeta cluster marathon getinfo "$MAR_ID" "host" "$MARATHON_SUBMIT")
    echo ""
    @go.log WARN "We now need to set the MariaDB Root Pass to something better and we will set this on $CURHOST"
    getpass "$APP_ID DB Root" MARIAROOT
cat > $APP_HOME/creds/db.sql << EOPASS
use mysql;
update user set password=PASSWORD("$MARIAROOT") where User='root';
flush privileges;
EOPASS
cat > $APP_HOME/node1/conf/pass.sh << EOSH
#!/bin/bash
mysql -uroot -p\$MYSQL_ROOT_PASSWORD < /etc/mysql/db.sql
EOSH
    chmod +x $APP_HOME/node1/conf/pass.sh

    cp $APP_HOME/creds/db.sql $APP_HOME/node1/conf/
    CID=$(ssh $CURHOST "sudo docker ps|grep galera|cut -d\" \" -f1")
    @go.log INFO "Setting new password on $CID of $CURHOST"
    ssh $CURHOST "sudo docker exec -t $CID /etc/mysql/pass.sh"
    sleep 5
    rm $APP_HOME/node1/conf/pass.sh
    rm $APP_HOME/node1/conf/db.sql
    echo ""
    @go.log INFO "Starting Nodes"
    for ND in $NODES; do
        if [ "$ND" != "$BOOT_NODE" ]; then
            @go.log INFO "Starting $ND and waiting 5 seconds"
            MAR_FILE="$APP_HOME/$ND/marathon.json"
            MAR_ID="${APP_ROLE}/${APP_ID}/$ND"
            submitstartsvc "RES" "$MAR_ID" "$MAR_FILE" "$MARATHON_SUBMIT"
            if [ "$RES" != "0" ]; then
                @go.log WARN "$MAR_ID not started - is it already running?"
            fi
            sleep 5
        fi
    done
    @go.log INFO "Galera Runnings, now waiting 15 seconds and going to reset the initial bootstrap node"
    sleep 15
    MAR_FILE="$APP_HOME/$BOOT_NODE/marathon.json"
    MAR_ID="${APP_ROLE}/${APP_ID}/node1"

    @go.log WARN "Ok, now we are going to stop the initial node, remove the flag for starting a new cluster, and then start it"
    stopsvc "RES" "$MAR_ID" "$MAR_FILE" "$MARATHON_SUBMIT"
    @go.log WARN "Updating Node1 Conf to nolonger start the New Cluster Bootstrap"
    sed -i  "s/\"--wsrep-new-cluster\"//g" $MAR_FILE
    echo "1" > $APP_HOME/creds/boot.txt
    echo ""
    @go.log WARN "Removing old node1"
    ./zeta cluster marathon destroy $MAR_ID $MARATHON_SUBMIT 1
    @go.log WARN "Starting node1"
    submitstartsvc "RES" "$MAR_ID" "$MAR_FILE" "$MARATHON_SUBMIT"
    @go.log INFO "Galera Cluster Runninng!"
else
    for ND in $NODES; do
        MAR_FILE="$APP_HOME/$ND/marathon.json"
        MAR_ID="${APP_ROLE}/${APP_ID}/$ND"
        STATE_FILE="${APP_HOME}/${ND}/data/grastate.dat"
        BS_SAFE=$(cat $STATE_FILE|grep "safe_to_bootstrap"|cut -d" " -f2)
        echo "Node: $ND - Safe to BS: $BS_SAFE"
        if [ "$BS_SAFE" == "1" ]; then
            BS_NODE="$ND"
        fi
    done
    echo "Safe to Bootstrap: $BS_NODE"
    BS_CONF="${APP_HOME}/$BS_NODE/conf/conf.d/mysql_server.cnf"
    GCOM=$(cat $BS_CONF|grep "wsrep-cluster-address")
    sed -i 's@wsrep-cluster-address=.*@wsrep-cluster-address="gcomm://"@g' $BS_CONF

    MAR_FILE="$APP_HOME/${BS_NODE}/marathon.json"
    MAR_ID="${APP_ROLE}/${APP_ID}/${BS_NODE}"
    submitstartsvc "RES" "$MAR_ID" "$MAR_FILE" "$MARATHON_SUBMIT"
    @go.log WARN "Waiting 30 seconds"
    sleep 30
    echo "Starting all nodes that are not $BS_NODE"
    for ND in $NODES; do
        if [ "$ND" != "$BS_NODE" ]; then
            echo "Starting $ND and then waiting 30 seconds"
            MAR_FILE="$APP_HOME/$ND/marathon.json"
            MAR_ID="${APP_ROLE}/${APP_ID}/$ND"
            submitstartsvc "RES" "$MAR_ID" "$MAR_FILE" "$MARATHON_SUBMIT"
            sleep 30
        fi
    done
    @go.log INFO "Waiting 60 seconds before fixing first node"
    sleep 60
    MAR_FILE="$APP_HOME/${BS_NODE}/marathon.json"
    MAR_ID="${APP_ROLE}/${APP_ID}/${BS_NODE}"
    stopsvc "RES" "$MAR_ID" "$MAR_FILE" "$MARATHON_SUBMIT"
    sed -i "s@wsrep-cluster-address=.*@$GCOM@g" $BS_CONF
    submitstartsvc "RES" "$MAR_ID" "$MAR_FILE" "$MARATHON_SUBMIT"

fi


cd $MYDIR

