#!/bin/bash

###############
# $APP Specific
echo "The next step will walk through instance defaults for ${APP_ID}"
echo ""
read -e -p "Please enter the CPU shares to use with $APP_NAME: " -i "2.0" APP_CPU
echo ""
read -e -p "Please enter the Marathon Memory limit to use with cortex: " -i "4096" APP_MEM
echo ""
read -e -p "How many instances of $APP_NAME do you wish to run: " -i "1" APP_CNT
echo ""
read -e -p "What user should we run cortext as: " -i "zetasvc${APP_ROLE}" APP_USER
echo ""
echo "We can generate a secret key, or you can enter one, this will be stored in application.conf"
echo ""
read -e -p "Generate secret key? (Answering N will prompt for a secret key (Y/N): " -i "Y" APP_GEN_KEY

echo ""
if [ "$APP_GEN_KEY" != "Y" ]; then
    read -e -p "Secret Key for Cortext (will be echoed to the screen): " APP_SECRET
else
    APP_SECRET=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1)
fi

PORTSTR="CLUSTER:tcp:30900:${APP_ROLE}:${APP_ID}:API Port for Cortex"
getport "CHKADD" "API Port for Cortex" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME instance $APP_ID with $PSTR"
fi


bridgeports "APP_PORT_JSON" "$APP_PORT" "$APP_PORTSTR"
haproxylabel "APP_HA_PROXY" "${APP_PORTSTR}"

APP_MAR_FILE="${APP_HOME}/marathon.json"
APP_CONF_DIR="$APP_HOME/conf"
APP_LOG_DIR="$APP_HOME/logs"
APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"
APP_CERT_LOC="$APP_HOME/certs"
CN_GUESS="${APP_ID}-${APP_ROLE}.marathon.slave.mesos"





mkdir -p $APP_CERT_LOC
mkdir -p $APP_CONF_DIR
mkdir -p $APP_LOG_DIR
sudo chown -R $APP_USER:$IUSER $APP_CONF_DIR
sudo chown -R $APP_USER:$IUSER $APP_LOG_DIR
sudo chown -R $APP_USER:$IUSER $APP_CERT_LOC
sudo chmod 770 $APP_CERT_LOC
sudo chmod 770 $APP_CONF_DIR
sudo chmod 770 $APP_LOG_DIR


# Doing Java for this app because PLAY uses Java
. $CLUSTERMOUNT/zeta/shared/zetaca/gen_java_keystore.sh

STRPROX=""
if [ "$ZETA_DOCKER_PROXY" != "" ]; then
    STRPROX="${STRPROX}global {"
    STRPROX="${STRPROX} proxy {"
    STRPROX="${STRPROX} http: \"${ZETA_DOCKER_PROXY}\","
    STRPROX="${STRPROX} http: \"${ZETA_DOCKER_PROXY}\""
    STRPROX="${STRPROX} }"
    STRPROX="${STRPROX} }"
fi


cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_PORT="${APP_PORT}"
EOL1

cat > $APP_CONF_DIR/application.conf << EOL2
# Secret key
# ~~~~~
# The secret key is used to secure cryptographics functions.
# If you deploy your application to several instances be sure to use the same key!
play.crypto.secret="$APP_SECRET"
http.port=disabled
https.port: ${APP_PORT}
play.server.https.keyStore {
    path: "/opt/cortex/certs/myKeyStore.jks"
    type: "JKS"
    password: "${KEYSTOREPASS}"
}

analyzer {
  path = "/opt/cortex/cortex/analyzers"
  config {
  $STRPROX
  }
}

EOL2

cat > $APP_CONF_DIR/run.sh << EOL3
#!/bin/bash
cd /opt/cortex/cortex
bin/cortex -Dconfig.file=/opt/cortex/etc/application.conf

EOL3
chmod +x $APP_CONF_DIR/run.sh

cat > $APP_MAR_FILE << EOL
{
  "id": "${APP_MAR_ID}",
  "cmd": "chown -R ${APP_USER}:${IUSER} /opt/cortex && su -c /opt/cortex/etc/run.sh ${APP_USER}",
  "cpus": ${APP_CPU},
  "mem": ${APP_MEM},
  "instances": ${APP_CNT},
  "labels": {
   $APP_HA_PROXY
   "CONTAINERIZER":"Docker"
  },
  "ports": [],
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
      { "containerPath": "/opt/cortex/etc", "hostPath": "${APP_CONF_DIR}", "mode": "RW" },
      { "containerPath": "/opt/cortex/cortex/logs", "hostPath": "${APP_LOG_DIR}", "mode": "RW" },
      { "containerPath": "/opt/cortex/certs", "hostPath": "${APP_CERT_LOC}", "mode":"RW"}
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


