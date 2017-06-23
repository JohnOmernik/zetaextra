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


APP_MAR_FILE="${APP_HOME}/marathon.json"

APP_DATA_DIR="$APP_HOME/data"
APP_LOG_DIR="$APP_HOME/log"
APP_RUN_DIR="$APP_HOME/run"

APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"



APP_API_URL="https://${APP_ID}-${APP_ROLE}.marathon.slave.mesos:8443"


mkdir -p $APP_DATA_DIR
mkdir -p $APP_LOG_DIR
mkdir -p $APP_RUN_DIR

sudo chown -R $IUSER:$IUSER $APP_DATA_DIR
sudo chown -R $IUSER:$IUSER $APP_LOG_DIR
sudo chown -R $IUSER:$IUSER $APP_RUN_DIR

sudo chmod 770 $APP_DATA_DIR
sudo chmod 770 $APP_RUN_DIR
sudo chmod 770 $APP_LOG_DIR

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
     "JVM_MAX_THREAD_STACK_SIZE": "1280k"
  },
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "${APP_IMG}",
      "network": "HOST"
    },
    "volumes": [
      { "containerPath": "/var/lib/unifi", "hostPath": "${APP_DATA_DIR}", "mode": "RW" },
      { "containerPath": "/var/run/unifi", "hostPath": "${APP_RUN_DIR}", "mode": "RW" },
      { "containerPath": "/var/log/unifi", "hostPath": "${APP_LOG_DIR}", "mode":"RW"}
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


