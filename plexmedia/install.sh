#!/bin/bash

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
read -e -p "How many instances of $APP_NAME do you wish to run: " -i "1" APP_CNT
echo ""
read -e -p "Please enter your plex claim token provided at https://www.plex.tv/claim: " APP_PLEX_CLAIM
echo ""

PORTS="32400 3005 8324 32469 1900 32410 32412 32413 32414"
SRV="/home/$IUSER/homecluster/zetago/conf/firewall/services.conf"

for P in $PORTS; do
    CHK=$(grep ":$P:" $SRV)
    if [ "$CHK" == "" ]; then
        echo "$P Not found we are good"
    else
        echo "$P found we have issues"
        @go.log FATAL "we need all our ports to be free. - Exiting"
    fi
done

@go.log WARN "Ports needed not found in services.conf, will add now"


for P in $PORTS; do
    echo "CLUSTER:tcp:${P}:${APP_ROLE}:${APP_ID}:Port for Unifi Video" >> $SRV
done


APP_MAR_FILE="${APP_HOME}/marathon.json"

APP_DATA_DIR="$APP_HOME/data"
APP_CONFIG_DIR="$APP_HOME/config"
APP_TRANSCODE_DIR="$APP_HOME/transcode"

@go.log INFO "Adding Transcode Volume"
VOL="${APP_DIR}.${APP_ROLE}.${APP_ID}.transcode"
fs_mkvol "RETCODE" "$APP_TRANSCODE_DIR" "$VOL" "775"


@go.log INFO "Adding Data Volume"
VOL="${APP_DIR}.${APP_ROLE}.${APP_ID}.data"
fs_mkvol "RETCODE" "$APP_DATA_DIR" "$VOL" "775"

@go.log INFO "Adding Config Volume"
VOL="${APP_DIR}.${APP_ROLE}.${APP_ID}.config"
fs_mkvol "RETCODE" "$APP_CONFIG_DIR" "$VOL" "775"


APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"


sudo chown -R $IUSER:$IUSER $APP_DATA_DIR
sudo chown -R $IUSER:$IUSER $APP_CONFIG_DIR
sudo chown -R $IUSER:$IUSER $APP_TRANSCODE_DIR

sudo chmod 770 $APP_DATA_DIR
sudo chmod 770 $APP_CONFIG_DIR
sudo chmod 770 $APP_TRANSCODE_DIR


cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_PORT="8443"
EOL1



cat > $APP_MAR_FILE << EOL
{
  "id": "${APP_MAR_ID}",
  "cpus": ${APP_CPU},
  "mem": ${APP_MEM},
  "instances": ${APP_CNT},
  "labels": {
   "CONTAINERIZER":"Docker"
  },
  "env": {
     "TZ": "America/Chicago",
     "PLEX_CLAIM": "$APP_PLEX_CLAIM"
  },
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "${APP_IMG}",
      "network": "HOST"
    },
    "volumes": [
      { "containerPath": "/data", "hostPath": "${APP_DATA_DIR}", "mode": "RW" },
      { "containerPath": "/transcode", "hostPath": "${APP_TRANSCODE_DIR}", "mode": "RW" },
      { "containerPath": "/config", "hostPath": "${APP_CONFIG_DIR}", "mode":"RW"}
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


