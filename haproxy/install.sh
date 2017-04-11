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

PORTSTR="CLUSTER:tcp:30900:${APP_ROLE}:${APP_ID}:HAProxy LB"
getport "CHKADD" "HAProxy LBx" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME instance $APP_ID with $PSTR"
fi


bridgeports "APP_PORT_JSON" "$APP_PORT" "$APP_PORTSTR"
haproxylabel "APP_HA_PROXY" "${APP_PORTSTR}"
portslist "APP_PORT_LIST" "$APP_PORTSTR"

APP_MAR_FILE="${APP_HOME}/marathon.json"
APP_CONF_DIR="$APP_HOME/conf"
APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"

mkdir -p $APP_CONF_DIR
sudo chown -R $APP_USER:$IUSER $APP_CONF_DIR
sudo chmod 770 $APP_CONF_DIR

APP_N=$(echo "$APP_NODES"|tr "," " ")

CNT=1
APP_SERVERS=""
for N in $APP_N; do
    APP_SERVERS="${APP_SERVERS}    server srv${CNT} $N"$'\n'
    CNT=$(($CNT+1))
done


cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_PORT="${APP_PORT}"
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

frontend localnodes
    bind *:${APP_PORT}
    mode tcp
    default_backend nodes
    timeout client          3m

backend nodes
    mode tcp
    balance roundrobin
    timeout connect        10s
    timeout server          3m
$APP_SERVERS
EOL2


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
        $APP_PORT_JSON
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


