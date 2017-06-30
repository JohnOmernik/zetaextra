#!/bin/bash

###############
# $APP Specific
echo "The next step will walk through instance defaults for ${APP_ID}"
echo ""
read -e -p "Please enter the CPU shares to use with $APP_NAME: " -i "1.0" APP_CPU
echo ""
read -e -p "Please enter the Marathon Memory limit to use with $APP_NAME: " -i "1024" APP_MEM
echo ""
read -e -p "How many instances of $APP_NAME do you wish to run: " -i "1" APP_CNT
echo ""


PORTS="7443 7445 7446 7447 7080 6666"



APP_MAR_FILE="${APP_HOME}/marathon.json"

APP_DATA_DIR="$APP_HOME/data"
APP_LOG_DIR="$APP_HOME/log"
APP_VIDEO_DIR="$APP_HOME/video"

APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"

APP_API_URL="https://${APP_ID}-${APP_ROLE}.marathon.slave.mesos:APP_HTTP_PORT"

mkdir -p $APP_DATA_DIR
mkdir -p $APP_LOG_DIR
mkdir -p $APP_VIDEO_DIR

sudo chown -R $IUSER:$IUSER $APP_DATA_DIR
sudo chown -R $IUSER:$IUSER $APP_LOG_DIR
sudo chown -R $IUSER:$IUSER $APP_VIDEO_DIR

sudo chmod 770 $APP_DATA_DIR
sudo chmod 770 $APP_RUN_DIR
sudo chmod 770 $APP_VIDEO_DIR

cat > ${APP_DATA_DIR}/system.properties << EOP
#Wed Apr 15 21:20:47 CEST 2015
app.session.timeout=240
#ems.livews.port=7445
#ems.livewss.port=7446
is_default=false
# app.http.port = 7080
# app.https.port = 7443
# ems.liveflv.port = 6666
# ems.rtmp.port = 1935
# ems.rtsp.port = 7447
EOP





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
     "JVM_MAX_THREAD_STACK_SIZE": "1280k",
     "PUID": "",
     "PGUD": "",
     "DEBUG": "1"
  },
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "${APP_IMG}",
      "network": "BRIDGE"
      "parameters": [
                { "key": "cap-add", "value": "SYS_ADMIN" },
                { "key": "cap-add", "value": "DAC_READ_SEARCH" }
            ],
    },
    "volumes": [
      { "containerPath": "/var/lib/unifi-video", "hostPath": "${APP_DATA_DIR}", "mode": "RW" },
      { "containerPath": "/usr/lib/unifi-video/data/videos", "hostPath": "${APP_VIDEO_DIR}", "mode": "RW" },
      { "containerPath": "/var/log/unifi-video", "hostPath": "${APP_LOG_DIR}", "mode":"RW"}
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


