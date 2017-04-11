#!/bin/bash

# Load the FS lib for this cluster
FS_LIB="lib${FS_PROVIDER}"
. "$_GO_USE_MODULES" $FS_LIB

###############
# $APP Specific
echo "The next step will walk through instance defaults for ${APP_ID}"
echo ""


read -e -p "Please enter the CPU shares to use with $APP_NAME: " -i "1.0" APP_CPU
echo ""
read -e -p "Please enter the Marathon Memory (MB) limit to use with $APP_NAME: " -i "2048" APP_MEM
echo ""
read -e -p "Please enter the number of nodes for your Galera Maria DB Cluster (Min 3): " -i "3" APP_NODE_CNT
echo ""
read -e -p "Please enter your Galera Cluster Name: " -i "galera-$APP_ROLE-$APP_ID" APP_CLUSTER_NAME
echo ""
APP_INNODB_MEM=$(echo "$(echo "$APP_MEM*0.80"|bc|cut -d"." -f1)*1024*1024"|bc)


echo "Galera Requires four ports (5 if you include the UDP) for operation"
echo "It's recommended that you use all CLUSTER ports for these and then expose an edge port for the Load Balancer (Next Step)"


SOME_COMMENTS="Main Port for Maria DB"
PORTSTR="CLUSTER:tcp:30306:${APP_ROLE}:${APP_ID}:$SOME_COMMENTS"
getport "CHKADD" "$SOME_COMMENTS" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_MAIN_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_MAIN_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME $PSTR"
fi

SOME_COMMENTS="Replication Port 1 (Main)for Galera"
PORTSTR="CLUSTER:udp,tcp:30567:${APP_ROLE}:${APP_ID}:$SOME_COMMENTS"
getport "CHKADD" "$SOME_COMMENTS" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_REP1_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_REP1_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME $PSTR"
fi

SOME_COMMENTS="Replication Port 2 for Galera"
PORTSTR="CLUSTER:tcp:30568:${APP_ROLE}:${APP_ID}:$SOME_COMMENTS"
getport "CHKADD" "$SOME_COMMENTS" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_REP2_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_REP2_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME $PSTR"
fi

SOME_COMMENTS="Replication Port 3 for Galera"
PORTSTR="CLUSTER:tcp:30444:${APP_ROLE}:${APP_ID}:$SOME_COMMENTS"
getport "CHKADD" "$SOME_COMMENTS" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_REP3_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_REP3_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME $PSTR"
fi

#SOME_COMMENTS="Replication Port 4 for Galera"
#PORTSTR="CLUSTER:udp:30569:${APP_ROLE}:${APP_ID}:$SOME_COMMENTS"
#getport "CHKADD" "$SOME_COMMENTS" "$SERVICES_CONF" "$PORTSTR"

#if [ "$CHKADD" != "" ]; then
#    getpstr "MYTYPE" "MYPROTOCOL" "APP_REP4_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
#    APP_REP4_PORTSTR="$CHKADD"
#else
#    @go.log FATAL "Failed to get Port for $APP_NAME $PSTR"
#fi

echo ""
echo "You have the ports required for the Galera Nodes, now we will ask for a port for the Load Balancer (this is where clients will connect to do so specifiy edge if needed)"
SOME_COMMENTS="Load Balancer Port for Galera Cluster"
PORTSTR="CLUSTER:tcp:30842:${APP_ROLE}:${APP_ID}:$SOME_COMMENTS"
getport "CHKADD" "$SOME_COMMENTS" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_LB_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_LB_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME $PSTR"
fi



bridgeports "APP_MAIN_PORT_JSON" "$APP_MAIN_PORT" "$APP_MAIN_PORTSTR"
bridgeports "APP_REP1_PORT_JSON" "$APP_REP1_PORT" "$APP_REP1_PORTSTR"
bridgeports "APP_REP2_PORT_JSON" "$APP_REP2_PORT" "$APP_REP2_PORTSTR"
bridgeports "APP_REP3_PORT_JSON" "$APP_REP3_PORT" "$APP_REP3_PORTSTR"
#bridgeports "APP_REP4_PORT_JSON" "4567" "$APP_REP4_PORTSTR"
bridgeports "APP_LB_PORT_JSON" "4567" "$APP_LB_PORTSTR"

haproxylabel "APP_NODE_HA_PROXY" "${APP_MAIN_PORTSTR}~${APP_REP1_PORTSTR}~${APP_REP2_PORTSTR}~${APP_REP3_PORTSTR}"
haproxylabel "APP_LB_HA_PROXY" "${APP_LB_PORTSTR}"

# Ports Done!



# Get default conf dir
mkdir -p ${APP_HOME}/default_conf
sudo docker pull $APP_IMG
CID=$(sudo docker run -d $APP_IMG sleep 15)

sudo docker cp $CID:/etc/mysql ${APP_HOME}/default_conf
sudo chown -R ${IUSER}:${IUSER} ${APP_HOME}/default_conf

# Now we setup each of the nodes with it's own directory

BOOT_NODE="0"

APP_CRED_DIR="${APP_HOME}/creds"
mkdir -p $APP_CRED_DIR
sudo chown -R ${IUSER}:${IUSER} $APP_CRED_DIR
sudo chmod 770 $APP_CRED_DIR
echo "0" > ${APP_HOME}/creds/boot.txt

APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"
cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_PORT="${APP_LB_PORT}"
EOL1

APP_SRV_LIST=""

for X in $(seq 1 $APP_NODE_CNT); do
    ND="node${X}"
    APP_ADDRESS="${ND}-${APP_ID}-${APP_ROLE}.marathon.slave.mesos"
    if [ "$APP_SRV_LIST" == "" ]; then
        APP_SRV_LIST="${APP_ADDRESS}:${APP_REP1_PORT}"
    else
        APP_SRV_LIST="${APP_SRV_LIST},${APP_ADDRESS}:${APP_REP1_PORT}"
    fi
done
echo "Galera Node Listing: $APP_SRV_LIST"

for X in $(seq 1 $APP_NODE_CNT); do
    ND="node${X}"
    mkdir -p ${APP_HOME}/${ND}
 

    @go.log INFO "Adding Node Volume for $ND"
    APP_DATA_DIR="${APP_HOME}/${ND}/data"
    VOL="${APP_DIR}.${APP_ROLE}.${APP_ID}.${ND}"
    fs_mkvol "RETCODE" "$APP_DATA_DIR" "$VOL" "775"
    sudo chown ${IUSER}:${IUSER} $APP_DATA_DIR
    sudo chmod 770 $APP_DATA_DIR

    if [ "$BOOT_NODE" == "0" ]; then
        APP_ARGS="\"args\": [\"--wsrep-new-cluster\"]"
        BOOT_NODE="1"
    else
        APP_ARGS="\"args\": []"
        # Trick to make it so non initial nodes don't init mysql
        mkdir -p ${APP_DATA_DIR}/mysql
    fi

    APP_CONF_DIR="${APP_HOME}/${ND}/conf"
    mkdir -p $APP_CONF_DIR
    sudo chown -R ${IUSER}:${IUSER} $APP_CONF_DIR
    sudo chmod  770 $APP_CONF_DIR

    cp -R ${APP_HOME}/default_conf/mysql/* $APP_CONF_DIR/
#    mv ${APP_CONF_DIR}/my.cnf ${APP_CONF_DIR}/my.cnf.old

    APP_LOG_DIR="${APP_HOME}/${ND}/logs"
    mkdir -p $APP_LOG_DIR
    sudo chown -R ${IUSER}:${IUSER} $APP_LOG_DIR
    sudo chmod 770 $APP_LOG_DIR

    APP_MAR_FILE="${APP_HOME}/${ND}/marathon.json"
    APP_MAR_ID="${APP_ROLE}/${APP_ID}/${ND}"
    APP_ADDRESS="${ND}-${APP_ID}-${APP_ROLE}.marathon.slave.mesos"

cat > ${APP_CONF_DIR}/conf.d/mysql_server.cnf << EOCONF
#
# Galera Cluster: mandatory settings
#

[server]
port=$APP_MAIN_PORT
bind-address=0.0.0.0
binlog_format=row
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2
innodb_locks_unsafe_for_binlog=1
query_cache_size=0
query_cache_type=0
innodb_buffer_pool_size=$APP_INNODB_MEM

[galera]
wsrep_on=ON
wsrep-cluster-name="$APP_CLUSTER_NAME"
wsrep_provider="/usr/lib/galera/libgalera_smm.so"
wsrep-cluster-address="gcomm://${APP_SRV_LIST}"
wsrep-sst-method=rsync
wsrep-node-address="${APP_ADDRESS}:${APP_REP1_PORT}"
wsrep-sst-receive-address="${APP_ADDRESS}:${APP_REP3_PORT}"
wsrep-provider-options="ist.recv_addr=${APP_ADDRESS}:${APP_REP2_PORT}"
wsrep-node-name="$ND"
#
# Optional setting
#

# Tune this value for your system, roughly 2x cores; see https://mariadb.com/kb/en/mariadb/galera-cluster-system-variables/#wsrep_slave_threads
# wsrep_slave_threads=1

# innodb_flush_log_at_trx_commit=0

EOCONF



cat > $APP_MAR_FILE << EOL
{
  "id": "${APP_MAR_ID}",
  "cpus": $APP_CPU,
  "mem": $APP_MEM,
  $APP_ARGS,
  "instances": 1,
  "constraints": [["hostname", "UNIQUE"]],
  "labels": {
   $APP_NODE_HA_PROXY
   "CONTAINERIZER":"Docker"
  },
  "env": {
    "MYSQL_INITDB_SKIP_TZINFO": "yes",
    "MYSQL_ROOT_PASSWORD": "AVeryStupidRootPasswordThatIsChanged!"
  },
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "${APP_IMG}",
      "network": "BRIDGE",
      "portMappings": [
        $APP_MAIN_PORT_JSON,
        $APP_REP1_PORT_JSON,
        $APP_REP2_PORT_JSON,
        $APP_REP3_PORT_JSON
      ]
    },
  "volumes": [
      {
        "containerPath": "/var/lib/mysql",
        "hostPath": "${APP_DATA_DIR}",
        "mode": "RW"
      },
      {
        "containerPath": "/creds",
        "hostPath": "${APP_CRED_DIR}",
        "mode": "RO"
      },
      {
        "containerPath": "/logs",
        "hostPath": "${APP_LOG_DIR}",
        "mode": "RW"
      },
      {
        "containerPath": "/etc/mysql",
        "hostPath": "${APP_CONF_DIR}",
        "mode": "RW"
      }
    ]
  }
}

EOL
done

##########
# Provide instructions for next steps
echo ""
echo ""
echo "$APP_NAME instance ${APP_ID} installed at ${APP_HOME} and ready to go"
echo "To start please run: "
echo ""
echo "$ ./zeta package start ${APP_HOME}/$APP_ID.conf"
echo ""
