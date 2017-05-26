#!/bin/bash

# Load the FS lib for this cluster

###############
# $APP Specific
echo "The next step will walk through instance defaults for ${APP_ID}"
echo ""
read -e -p "Please enter the CPU shares to use with $APP_NAME: " -i "1.0" APP_CPU
echo ""
read -e -p "Please enter the Marathon Memory limit to use with $APP_NAME: " -i "1024" APP_MEM
echo ""
read -e -p "What user should we run Grafana as: " -i "zetasvc$APP_ROLE" APP_USER

APP_GROUP="zeta${APP_ROLE}zeta"

PORTSTR="CLUSTER:tcp:22024:${APP_ROLE}:${APP_ID}:Main port for Grafana"
getport "CHKADD" "Main Grafana Port" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME instance $APP_ID with $PSTR"
fi
bridgeports "APP_PORT_JSON" "3000" "$APP_PORTSTR"

haproxylabel "APP_HA_PROXY" "${APP_PORTSTR}"
portslist "APP_PORT_LIST" "$APP_PORTSTR"

APP_MAR_FILE="${APP_HOME}/marathon.json"
APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"

APP_CONF_DIR="$APP_HOME/conf"
APP_PLUGINS_DIR="$APP_HOME/plugins"
APP_DATA_DIR="$APP_HOME/data"
APP_LOG_DIR="$APP_HOME/log"


APP_SUB=$(echo "$APP_MAR_ID"|sed "s@/@ @g")
APP_OUT=$(echo "$APP_SUB"| sed 's/ /\n/g' | tac | sed ':a; $!{N;ba};s/\n/ /g'|tr " " "-")

APP_API_URL="http://${APP_OUT}.marathon.slave.mesos:$APP_PORT"


mkdir -p $APP_CONF_DIR
sudo chown -R $APP_USER:$IUSER $APP_CONF_DIR
sudo chmod 770 $APP_CONF_DIR

mkdir -p $APP_DATA_DIR
sudo chown -R $APP_USER:$IUSER $APP_DATA_DIR
sudo chmod 770 $APP_DATA_DIR

mkdir -p $APP_LOG_DIR
sudo chown -R $APP_USER:$IUSER $APP_LOG_DIR
sudo chmod 770 $APP_LOG_DIR

mkdir -p $APP_PLUGINS_DIR
sudo chown -R $APP_USER:$IUSER $APP_PLUGINS_DIR
sudo chmod 770 $APP_PLUGINS_DIR

cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_HOST="${APP_HOSTNAME}"
export ZETA_${APP_NAME}_${APP_ID}_PORT="${APP_PORT}"
EOL1

cat > $APP_CONF_DIR/grafana.ini << EOI
[paths]
data = "/var/lib/grafana"
logs = "/var/log/grafana"
plugins = "/opt/grafana"
EOI

cat > $APP_CONF_DIR/run.sh << EOR
#!/bin/bash -e

echo "Running as $APP_USER"
id $APP_USER

: "\${GF_PATHS_DATA:=/var/lib/grafana}"
: "\${GF_PATHS_LOGS:=/var/log/grafana}"
: "\${GF_PATHS_PLUGINS:=/var/lib/grafana/plugins}"

chown -R ${APP_USER}:${IUSER} "\$GF_PATHS_DATA" "\$GF_PATHS_LOGS"
chown -R ${APP_USER}:${IUSER} /etc/grafana

if [ ! -z \${GF_AWS_PROFILES+x} ]; then
    mkdir -p ~${APP_USER}/.aws/
    touch ~${APP_USR}/.aws/credentials

    for profile in \${GF_AWS_PROFILES}; do
        access_key_varname="GF_AWS_\${profile}_ACCESS_KEY_ID"
        secret_key_varname="GF_AWS_\${profile}_SECRET_ACCESS_KEY"
        region_varname="GF_AWS_\${profile}_REGION"

        if [ ! -z "\${!access_key_varname}" -a ! -z "\${!secret_key_varname}" ]; then
            echo "[\${profile}]" >> ~${APP_USER}/.aws/credentials
            echo "aws_access_key_id = \${!access_key_varname}" >> ~${APP_USER}/.aws/credentials
            echo "aws_secret_access_key = \${!secret_key_varname}" >> ~${APP_USER}/.aws/credentials
            if [ ! -z "\${!region_varname}" ]; then
                echo "region = \${!region_varname}" >> ~${APP_USER}/.aws/credentials
            fi
        fi
    done

    chown $APP_USER:$IUSER -R ~${APP_USER}/.aws
    chmod 600 ~$APP_USER/.aws/credentials
fi

if [ ! -z "\${GF_INSTALL_PLUGINS}" ]; then
  OLDIFS=\$IFS
  IFS=','
  for plugin in \${GF_INSTALL_PLUGINS}; do
    IFS=\$OLDIFS
    grafana-cli  --pluginsDir "\${GF_PATHS_PLUGINS}" plugins install \${plugin}
  done
fi

su -c "/usr/sbin/grafana-server --homepath=/usr/share/grafana --config=/etc/grafana/grafana.ini" $APP_USER

EOR
chmod +x $APP_CONF_DIR/run.sh


cat > $APP_MAR_FILE << EOL
{
  "id": "${APP_MAR_ID}",
  "cmd": "/etc/grafana/run.sh",
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
        $APP_PORT_JSON
      ]
    },
    "volumes": [
      { "containerPath": "/etc/grafana", "hostPath": "${APP_CONF_DIR}", "mode": "RW" },
      { "containerPath": "/var/lib/grafana", "hostPath": "${APP_DATA_DIR}", "mode": "RW" },
      { "containerPath": "/var/log/grafana", "hostPath": "${APP_LOG_DIR}", "mode": "RW" },
      { "containerPath": "/opt/grafana", "hostPath": "${APP_PLUGINS_DIR}", "mode": "RW" }
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


