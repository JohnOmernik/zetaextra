#!/bin/bash

###############
# $APP Specific
echo "The next step will walk through instance defaults for ${APP_ID}"
echo ""
read -e -p "Please enter the CPU shares to use with $APP_NAME: " -i "1.0" APP_CPU
echo ""
read -e -p "Please enter the Marathon Memory limit to use with cortex: " -i "512" APP_MEM
echo ""
read -e -p "How many instances of $APP_NAME do you wish to run: " -i "1" APP_CNT
echo ""
read -e -p "Please enter a list of Nodes and ports for back end servers... format: node1:port1,node2:port2,node3:port3: " APP_NODES
echo ""
echo "If using Haproxy for a frontend to something like galera cluster, we can do two ports one for writing to ensure locks don't get in the way"
echo "This does two things:"
echo ""
echo "1. Port 1 can be used for write heavy applications, this Prefers one node (typically the first node, node1) for writes. If this node is down, it will move to another node (Still HA, just not balanced HA)"
echo "2. Port 2 is used for read heavy applications. This truly round robins the connections, thus distributing reads"
echo ""
echo "If this is not needed, answer N to the next question, else answer Y to specify two ports"
echo ""
read -e -p "Use Two ports for HA Proxy? (Y/N): " -i "N" APP_TWO_PORTS
echo ""


PORTSTR="CLUSTER:tcp:30900:${APP_ROLE}:${APP_ID}:HAProxy General Port LB Port"
getport "CHKADD" "HAProxy LB Gen" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_GEN_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_GEN_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME instance $APP_ID with $PSTR"
fi
bridgeports "APP_GEN_PORT_JSON" "$APP_GEN_PORT" "$APP_GEN_PORTSTR"

if [ "$APP_TWO_PORTS" == "Y" ]; then
    PORTSTR="CLUSTER:tcp:30901:${APP_ROLE}:${APP_ID}:HAProxy Write Specific Port LB Port"
    getport "CHKADD" "HAProxy LB Wrt" "$SERVICES_CONF" "$PORTSTR"

    if [ "$CHKADD" != "" ]; then
        getpstr "MYTYPE" "MYPROTOCOL" "APP_WRT_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
        APP_WRT_PORTSTR="$CHKADD"
    else
        @go.log FATAL "Failed to get Port for $APP_NAME instance $APP_ID with $PSTR"
    fi
    bridgeports "APP_WRT_PORT_JSON" "$APP_WRT_PORT" "$APP_WRT_PORTSTR"
    haproxylabel "APP_HA_PROXY" "${APP_GEN_PORTSTR}~${APP_WRT_PORTSTR}"
    portslist "APP_PORT_LIST" "$APP_GEN_PORTSTR~${APP_WRT_PORTSTR}"
    MAR_PORTS="${APP_GEN_PORT_JSON},$APP_WRT_PORT_JSON"

else
    haproxylabel "APP_HA_PROXY" "${APP_GEN_PORTSTR}"
    portslist "APP_PORT_LIST" "$APP_GEN_PORTSTR"
    MAR_PORTS="$APP_GEN_PORT_JSON"

fi

APP_MAR_FILE="${APP_HOME}/marathon.json"
APP_CONF_DIR="$APP_HOME/conf"
APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"

APP_HOSTNAME="${APP_ID}.${APP_ROLE}.marathon.slave.mesos"

mkdir -p $APP_CONF_DIR
sudo chown -R $APP_USER:$IUSER $APP_CONF_DIR
sudo chmod 770 $APP_CONF_DIR

APP_N=$(echo "$APP_NODES"|tr "," " ")

CNT=1
APP_READ_SERVERS=""
for N in $APP_N; do
    APP_READ_SERVERS="${APP_READ_SERVERS}    server srv${CNT} $N"$'\n'
    CNT=$(($CNT+1))
done

CNT=1
APP_WRITE_SERVERS=""
for N in $APP_N; do
    if [ "$CNT" == "1" ]; then
        EXTRA="check backup"
    else
        EXTRA="backup"
    fi
    APP_WRITE_SERVERS="${APP_WRITE_SERVERS}    server srv${CNT} $N $EXTRA"$'\n'
    CNT=$(($CNT+1))
done


if [ "$APP_TWO_PORTS" == "Y" ]; then
cat > $APP_ENV_FILE << EOL14
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_HOST="${APP_HOSTNAME}"
export ZETA_${APP_NAME}_${APP_ID}_GEN_PORT="${APP_GEN_PORT}"
export ZETA_${APP_NAME}_${APP_ID}_WRT_PORT="${APP_WRT_PORT}"
EOL14
cat > $APP_CONF_DIR/haproxy.cfg << EOL12
global
        maxconn 4096
defaults
        mode    tcp
        balance leastconn
        timeout client      30000ms
        timeout server      30000ms
        timeout connect      3000ms
        retries 3

frontend readha
    bind *:${APP_GEN_PORT}
    mode tcp
    default_backend readnodes
    timeout client          3m

frontend writeha
    bind *:${APP_WRT_PORT}
    mode tcp
    default_backend writenodes
    timeout client          3m

backend readnodes
    mode tcp
    balance roundrobin
    timeout connect        10s
    timeout server          3m
$APP_READ_SERVERS

backend writenodes
    mode tcp
    balance roundrobin
    timeout connect        10s
    timeout server          3m
$APP_WRITE_SERVERS
EOL12

else

cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_HOST="${APP_HOSTNAME}"
export ZETA_${APP_NAME}_${APP_ID}_GEN_PORT="${APP_GEN_PORT}"
EOL1



cat > $APP_CONF_DIR/haproxy.cfg << EOL2
global
        maxconn 4096
defaults
        mode    tcp
        balance leastconn
        timeout client      30000ms
        timeout server      30000ms
        timeout connect      3000ms
        retries 3

frontend readha
    bind *:${APP_GEN_PORT}
    mode tcp
    default_backend nodes
    timeout client          3m

backend readnodes
    mode tcp
    balance roundrobin
    timeout connect        10s
    timeout server          3m
$APP_READ_SERVERS
EOL2
fi

cat > $APP_MAR_FILE << EOL
{
  "id": "${APP_MAR_ID}",
  "cmd": "haproxy -f /usr/local/etc/haproxy/haproxy.cfg",
  "cpus": ${APP_CPU},
  "mem": ${APP_MEM},
  "instances": ${APP_CNT},
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
        $MAR_PORTS
      ]
    },
    "volumes": [
      { "containerPath": "/usr/local/etc/haproxy", "hostPath": "${APP_CONF_DIR}", "mode": "RW" }
    ]

  }
}
EOL


##########
# Provide instructions for next steps
echo ""
echo ""
echo "$APP_NAME instance ${APP_ID} installed at ${APP_HOME} and ready to go"
echo "To start please run: "
echo ""
echo "$ ./zeta package start ${APP_HOME}/$APP_ID.conf"
echo ""


