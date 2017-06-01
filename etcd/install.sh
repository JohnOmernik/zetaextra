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
read -e -p "Please enter the Marathon Memory limit to use with $APP_NAME: " -i "2048" APP_MEM
echo ""
read -e -p "How many etcd nodes do you wish to run (3 min recommended): " -i "3" APP_NODE_CNT
echo ""
 
PORTSTR="CLUSTER:tcp:22379:${APP_ROLE}:${APP_ID}:Client port for etcd"
getport "CHKADD" "Client Port" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_CLIENT_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_CLIENT_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME instance $APP_ID with $PSTR"
fi

PORTSTR="CLUSTER:tcp:22380:${APP_ROLE}:${APP_ID}:Peer port for etcd"
getport "CHKADD" "Peer Port" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_PEER_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_PEER_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME instance $APP_ID with $PSTR"
fi

bridgeports "APP_CLIENT_PORT_JSON" "2379" "$APP_CLIENT_PORTSTR"
bridgeports "APP_PEER_PORT_JSON" "2380" "$APP_PEER_PORTSTR"

haproxylabel "APP_HA_PROXY" "${APP_CLIENT_PORTSTR}~${APP_PEER_PORTSTR}"
portslist "APP_PORT_LIST" "${APP_CLIENT_PORTSTR}~${APP_PEER_PORTSTR}"

APP_MAR_FILE="DIRECTORY"
APP_MAR_DIR="${APP_HOME}/marathon_files"

APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"
APP_DATA_DIR="${APP_HOME}/data"
APP_BIN_DIR="$APP_HOME/bin"

mkdir -p $APP_MAR_DIR
sudo chown -R $IUSER:$IUSER $APP_MAR_DIR
sudo chmod 770 $APP_MAR_DIR

mkdir -p $APP_DATA_DIR
sudo chown -R $IUSER:$IUSER $APP_DATA_DIR
sudo chown 775 $APP_DATA_DIR

mkdir -p $APP_BIN_DIR
sudo chown -R $IUSER:$IUSER $APP_BIN_DIR
sudo chown 775 $APP_BIN_DIR

@go.log INFO "Creating Volumes for $APP_NODE_CNT instances of etcd data dirs"

INIT_CLUSTER=""
INIT_CLUSTER_TOKEN="etcd-${APP_ROLE}-${APP_ID}"

for N in `seq 1 "$APP_NODE_CNT"`; do
    NODE="etcd$N"

    NODE_MAR_ID="${APP_MAR_ID}/${NODE}"

    NODE_SUB=$(echo "$NODE_MAR_ID"|sed "s@/@ @g")
    NODE_OUT=$(echo "$NODE_SUB"| sed 's/ /\n/g' | tac | sed ':a; $!{N;ba};s/\n/ /g'|tr " " "-")
    NODE_HOST="${NODE_OUT}.marathon.slave.mesos"

    if [ "$INIT_CLUSTER" == "" ]; then
        INIT_CLUSTER="${NODE}=http://${NODE_HOST}:${APP_PEER_PORT}"
    else
        INIT_CLUSTER="${INIT_CLUSTER},${NODE}=http://${NODE_HOST}:${APP_PEER_PORT}"
    fi


    VOL="${APP_DIR}.${APP_ROLE}.${APP_ID}.${NODE}"
    VOLDIR="${APP_DATA_DIR}/$NODE"

    @go.log INFO "Creating volume for $NODE"
    fs_mkvol "RETCODE" "$VOLDIR" "$VOL" "775"
    sudo chown ${IUSER}:${IUSER} $VOLDIR
    sudo chmod 770 $VOLDIR


done

cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_CLIENT_PORT="${APP_CLIENT_PORT}"
export ZETA_${APP_NAME}_${APP_ID}_PEER_PORT="${APP_PEER_PORT}"
EOL1

cat > ${APP_BIN_DIR}/etcdnode.sh << EOB
#!/bin/sh
CHK=\`nslookup \$MYHOSTNAME|grep Address\`
while [ "\$CHK" == "" ]; do

    echo "Sleeping 2 seconds and checking for \$MYHOSTNAME again"
    sleep 2
    CHK=\`nslookup \$MYHOSTNAME|grep Address\`
done
echo "Found \$MYHOSTNAME now starting etcd"
echo ""
/usr/local/bin/etcd --data-dir=/etcd-data --name \$MYNAME --advertise-client-urls http://\$MYHOSTNAME:$APP_CLIENT_PORT --listen-client-urls http://0.0.0.0:2379 --initial-advertise-peer-urls http://\$MYHOSTNAME:$APP_PEER_PORT --listen-peer-urls http://0.0.0.0:2380 --initial-cluster=${INIT_CLUSTER} --initial-cluster-token $INIT_CLUSTER_TOKEN -initial-cluster-state new
EOB
chmod +x ${APP_BIN_DIR}/etcdnode.sh

for N in `seq 1 "$APP_NODE_CNT"`; do
    NODE="etcd$N"
    NODE_MAR_ID="${APP_MAR_ID}/${NODE}"

    NODE_SUB=$(echo "$NODE_MAR_ID"|sed "s@/@ @g")
    NODE_OUT=$(echo "$NODE_SUB"| sed 's/ /\n/g' | tac | sed ':a; $!{N;ba};s/\n/ /g'|tr " " "-")
    NODE_HOST="${NODE_OUT}.marathon.slave.mesos"

cat > $APP_MAR_DIR/${NODE}.json << EOL
{
  "id": "${NODE_MAR_ID}",
  "cpus": ${APP_CPU},
  "mem": ${APP_MEM},
  "cmd": "/etcdbin/etcdnode.sh",
  "instances": 1,
  "constraints": [["hostname", "UNIQUE"]],
  "env": {
    "MYNAME": "$NODE",
    "MYHOSTNAME": "$NODE_HOST"
  },
  "labels": {
   $APP_HA_PROXY
   "CONTAINERIZER":"Docker"
  },
  $APP_PORT_LIST
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "${APP_IMG}",
      "network": "BRIDGE",
      "portMappings": [
        $APP_CLIENT_PORT_JSON,
        $APP_PEER_PORT_JSON
      ]
    },
    "volumes": [
      { "containerPath": "/etcdbin", "hostPath": "${APP_BIN_DIR}", "mode": "RO" },
      { "containerPath": "/etc/ssl/certs", "hostPath": "/usr/share/ca-certificates", "mode": "RO" },
      { "containerPath": "/etcd-data", "hostPath": "${APP_DATA_DIR}/$NODE", "mode": "RW" }
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


