#!/bin/bash

echo "This is used to add a node"
echo ""
echo "Please enter the host you wish to add a Rancher Agent to:"
echo ""
read -e -p "What is the IP of the Host to add Rancher Agent to: " AGENT_NODE
echo ""
NODE_CHK=$(ssh $AGENT_NODE "sudo docker ps|grep rancher|grep agent")
if [ "$NODE_CHK" != "" ]; then
    @go.log FATAL "Agent running on $AGENT_NODE - $NODE_CHK"
fi

APP_MAR_FILE="$APP_MAR_DIR/agent_$AGENT_NODE.json"
if [ -f "$APP_MAR_FILE" ]; then
    @go.log FATAL "Agent JSON Already Created"
fi

APP_BIN_DIR="$APP_HOME/bin"

read -e -p "How much Ram should this Rancher Agent limit?: " -i "2048" APP_MEM
APP_RANCHER_MEM=$(echo "$APP_MEM*1024*1024"|bc|cut -d"." -f1)
echo ""
read -e -p "What should we use for Marathon Limits for CPU?: " -i "1.0" APP_CPU
APP_RANCHER_CPU=$(echo "$APP_CPU*1000"|bc|cut -d"." -f1)
echo ""
read -e -p "What should we use for Rancher Local Storage limits?: " -i "5000" APP_RANCHER_STORAGE
echo ""
read -e -p "Please enter the Rancher API URL Provided: " API_URL

LIB_CHK=$(ssh $AGENT_NODE "ls -1 /var/lib|grep rancher")
if [ "$LIB_CHK" != "" ]; then
    @go.log WARN "There already appears to be a /var/lib/rancher even though the agent isn't running on $AGENT_NODE"
    read -e -p "Should we remove this /var/lib/rancher directory? This is destructive and probably unwise... (Y/N): " -i "N" LIB_CLEAN
    if [ "$LIB_CLEAN" != "Y" ]; then
        @go.log FATAL "We are exiting so we don't hurt something"
    else
        @go.log WARN "Removing /var/lib/rancher on $AGENT_NODE"
        ssh $AGENT_NODE "sudo rm -rf /var/lib/rancher"
    fi
fi
echo "$APP_PKG_BASE/${APP_VERS_FILE}"

. $APP_PKG_BASE/${APP_VERS_FILE}
echo "$APP_IMG"
echo ""
APP_MAR_ID="prod/$APP_ID/agent$AGENT_NODE"

# APP_ARGS="\"args\": [\"$API_URL\"]"

APP_MAR_FILE="$APP_MAR_DIR/agent_$AGENT_NODE.json"
cat > $APP_MAR_FILE << EOMAR
{
  "id": "${APP_MAR_ID}",
  "cpus": $APP_CPU,
  "mem": $APP_MEM,
  "args": ["--", "/appbin/start.sh"],
  "instances": 1,
  "taskKillGracePeriodSeconds": 120,
  "env": {
   "OURRANCH": "$API_URL",
   "CATTLE_MEMORY_OVERRIDE":"$APP_RANCHER_MEM",
   "CATTLE_MILLI_CPU_OVERRIDE": "$APP_RANCHER_CPU",
   "CATTLE_AGENT_IP": "$AGENT_NODE",
   "CATTLE_LOCAL_STORAGE_MB_OVERRIDE": "$APP_RANCHER_STORAGE"
  },
  "constraints": [["hostname","LIKE","$AGENT_NODE"],["hostname","UNIQUE"]],
  "labels": {
   "CONTAINERIZER":"Rancher"
  },
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "${APP_IMG}",
      "network": "BRIDGE",
      "privileged": true
    },
    "volumes": [
      {
        "containerPath": "/var/run/docker.sock",
        "hostPath": "/var/run/docker.sock",
        "mode": "RW"
      },
      {
        "containerPath": "/var/lib/rancher",
        "hostPath": "/var/lib/rancher",
        "mode": "RW"
      },
      {
        "containerPath": "/appbin",
        "hostPath": "$APP_BIN_DIR",
        "mode": "RO"
      }
    ]
  }
}

EOMAR

@go.log WARN "Marathon File completed, you can start by running:"
echo ""
echo "./zeta cluster marathon submit $APP_MAR_FILE ${MARTHON_SUBMIT} 1"
echo ""


