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

PORTSTR="CLUSTER:tcp:22023:${APP_ROLE}:${APP_ID}:Main port for Influx DB"
getport "CHKADD" "Main Influx Port" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_MAIN_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_MAIN_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME instance $APP_ID with $PSTR"
fi
bridgeports "APP_MAIN_PORT_JSON" "8086" "$APP_MAIN_PORTSTR"

haproxylabel "APP_HA_PROXY" "${APP_MAIN_PORTSTR}"
portslist "APP_PORT_LIST" "$APP_MAIN_PORTSTR"

APP_HOSTNAME="${APP_ID}.${APP_ROLE}.marathon.slave.mesos"
APP_MAR_FILE="${APP_HOME}/marathon.json"
APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"
APP_CONF_DIR="$APP_HOME/conf"
APP_API_URL="$APP_HOSTNAME:$APP_MAIN_PORT"

mkdir -p $APP_CONF_DIR
sudo chown -R $APP_USER:$IUSER $APP_CONF_DIR
sudo chmod 770 $APP_CONF_DIR

APP_WAL_DIR="${APP_HOME}/wal"
APP_META_DIR="${APP_HOME}/meta"
APP_DATA_DIR="${APP_HOME}/data"

@go.log INFO "Adding Volume for Write Ahead Log Directory"
VOL="${APP_DIR}.${APP_ROLE}.${APP_ID}.wal"
fs_mkvol "RETCODE" "$APP_WAL_DIR" "$VOL" "775"
sudo chown ${IUSER}:${IUSER} $APP_WAL_DIR
sudo chmod 770 $APP_WAL_DIR

@go.log INFO "Adding Volume for Meta Directory"
VOL="${APP_DIR}.${APP_ROLE}.${APP_ID}.meta"
fs_mkvol "RETCODE" "$APP_META_DIR" "$VOL" "775"
sudo chown ${IUSER}:${IUSER} $APP_META_DIR
sudo chmod 770 $APP_META_DIR

@go.log INFO "Adding Volume for Data Directory"
VOL="${APP_DIR}.${APP_ROLE}.${APP_ID}.data"
fs_mkvol "RETCODE" "$APP_DATA_DIR" "$VOL" "775"
sudo chown ${IUSER}:${IUSER} $APP_DATA_DIR
sudo chmod 770 $APP_DATA_DIR

cat > ${APP_CONF_DIR}/influxdb.conf << EOC
[meta]
  dir = "/var/lib/influxdb/meta"

[data]
  dir = "/var/lib/influxdb/data"
  engine = "tsm1"
  wal-dir = "/var/lib/influxdb/wal"
EOC

cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_HOST="${APP_HOSTNAME}"
export ZETA_${APP_NAME}_${APP_ID}_MAIN_PORT="${APP_MAIN_PORT}"
EOL1


cat > $APP_MAR_FILE << EOL
{
  "id": "${APP_MAR_ID}",
  "cpus": ${APP_CPU},
  "mem": ${APP_MEM},
  "instances": 1,
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
        $APP_MAIN_PORT_JSON
      ]
    },
    "volumes": [
      { "containerPath": "/etc/influxdb", "hostPath": "${APP_CONF_DIR}", "mode": "RW" },
      { "containerPath": "/var/lib/influxdb/wal", "hostPath": "${APP_WAL_DIR}", "mode": "RW" },
      { "containerPath": "/var/lib/influxdb/meta", "hostPath": "${APP_META_DIR}", "mode": "RW" },
      { "containerPath": "/var/lib/influxdb/data", "hostPath": "${APP_DATA_DIR}", "mode": "RW" }
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


