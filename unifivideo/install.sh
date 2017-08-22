#!/bin/bash

FS_LIB="lib${FS_PROVIDER}"
. "$_GO_USE_MODULES" $FS_LIB
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


PORTS="7448 7445 7446 7447 7080 6666"


MYGO="$_GO_SCRIPT"

GO_ROOT=$(echo "$MYGO"|sed -r "s@/zeta$@@g")
SRV="$GO_ROOT/conf/firewall/services.conf"


PORTS="7448 7445 7446 7447 7080 6666"

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
APP_LOG_DIR="$APP_HOME/log"
APP_VIDEO_DIR="$APP_HOME/video"

@go.log INFO "Adding Video Volume"
VOL="${APP_DIR}.${APP_ROLE}.${APP_ID}.video"
fs_mkvol "RETCODE" "$APP_VIDEO_DIR" "$VOL" "775"


@go.log INFO "Adding Data Volume"
VOL="${APP_DIR}.${APP_ROLE}.${APP_ID}.data"
fs_mkvol "RETCODE" "$APP_DATA_DIR" "$VOL" "775"

mkdir -p $APP_LOG_DIR

APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"

APP_API_URL="https://${APP_ID}-${APP_ROLE}.marathon.slave.mesos:7448"

sudo chown -R $IUSER:$IUSER $APP_DATA_DIR
sudo chown -R $IUSER:$IUSER $APP_LOG_DIR
sudo chown -R $IUSER:$IUSER $APP_VIDEO_DIR

sudo chmod 770 $APP_DATA_DIR
sudo chmod 770 $APP_LOG_DIR
sudo chmod 770 $APP_VIDEO_DIR

cat > ${APP_DATA_DIR}/system.properties << EOP
# set at install on zeta
app.session.timeout=240
ems.livews.port=7445
ems.livewss.port=7446
is_default=false
app.http.port = 7080
app.https.port = 7448
ems.liveflv.port = 6666
#ems.rtmp.port = 1935
ems.rtsp.port = 7447
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
     "PUID": "2500",
     "PGUD": "2500",
     "DEBUG": "1"
  },
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "${APP_IMG}",
      "network": "HOST",
      "parameters": [
                { "key": "cap-add", "value": "SYS_ADMIN" },
                { "key": "cap-add", "value": "DAC_READ_SEARCH" },
                { "key": "security-opt", "value": "apparmor:unconfined" }
            ]
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


