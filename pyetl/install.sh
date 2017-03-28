#!/bin/bash

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
read -e -p "What user should we run $APP_NAME as: " -i "zetasvc${APP_ROLE}" APP_USER
echo ""


echo "We can generate a secret key, or you can enter one, this will be stored in superset_config.py"
echo ""
read -e -p "Generate secret key? (Answering N will prompt for a secret key (Y/N): " -i "Y" APP_GEN_KEY
echo ""
if [ "$APP_GEN_KEY" != "Y" ]; then
    read -e -p "Secret Key for Cortext (will be echoed to the screen): " APP_SECRET
else
    APP_SECRET=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1)
fi

PORTSTR="CLUSTER:tcp:30422:${APP_ROLE}:${APP_ID}:HTTPS Port for $APP_NAME"
getport "CHKADD" "HTTPS Port for $APP_NAME" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME instance $APP_ID with $PSTR"
fi

APP_API_URL="http://$APP_ID-$APP_ROLE.marathon.slave.mesos:$APP_PORT"

bridgeports "APP_PORT_JSON" "$APP_PORT" "$APP_PORTSTR"
haproxylabel "APP_HA_PROXY" "${APP_PORTSTR}"
portslist "APP_PORT_LIST" "${APP_PORTSTR}"

APP_MAR_FILE="${APP_HOME}/marathon.json"
APP_DATA_DIR="$APP_HOME/data"
APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"

mkdir -p $APP_DATA_DIR
sudo chown -R $APP_USER:$IUSER $APP_DATA_DIR
sudo chmod 770 $APP_DATA_DIR

cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_PORT="${APP_PORT}"
EOL1

cat > $APP_DATA_DIR/superset_config.py << EOL2
#---------------------------------------------------------
# Superset specific config
#---------------------------------------------------------
ROW_LIMIT = 5000
SUPERSET_WORKERS = 4

SUPERSET_WEBSERVER_PORT = $APP_PORT
#---------------------------------------------------------

#---------------------------------------------------------
# Flask App Builder configuration
#---------------------------------------------------------
# Your App secret key
SECRET_KEY = '$APP_SECRET'

# The SQLAlchemy connection string to your database backend
# This connection defines the path to the database that stores your
# superset metadata (slices, connections, tables, dashboards, ...).
# Note that the connection information to connect to the datasources
# you want to explore are managed directly in the web UI
SQLALCHEMY_DATABASE_URI = 'sqlite:////opt/superset/superset.db'

# Flask-WTF flag for CSRF
CSRF_ENABLED = True

# Set this API key to enable Mapbox visualizations
MAPBOX_API_KEY = ''

EOL2

cat > $APP_DATA_DIR/runsrv.sh << EOL3
#!/bin/bash
cd /opt/superset
superset runserver

EOL3
chmod +x $APP_DATA_DIR/runsrv.sh

cat > $APP_MAR_FILE << EOL
{
  "id": "${APP_MAR_ID}",
  "cmd": "mkdir -p /home/${APP_USER} && chown -R ${APP_USER}:${IUSER} /home/${APP_USER} && chown -R ${APP_USER}:${IUSER} /opt/superset && su -c /opt/superset/runsrv.sh ${APP_USER}",
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
      { "containerPath": "/opt/superset", "hostPath": "${APP_DATA_DIR}", "mode": "RW" }
    ]

  }
}
EOL

@go.log INFO "Superset conf files are all installed and configed, but Superset requires some interactive work to be complete, we will run this now"
echo ""
@go.log INFO "The first step is to create an admin user, this will ask for admin usernames, passwords etc"
sudo docker run -it --rm -v=${APP_DATA_DIR}:/opt/superset:rw $APP_IMG fabmanager create-admin --app superset
echo ""
@go.log INFO "Next we run the DB Upgrade"
sleep 2
sudo docker run -it --rm -v=${APP_DATA_DIR}:/opt/superset:rw $APP_IMG superset db upgrade
echo ""
@go.log INFO "Next we init all DBs"
sleep 2
sudo docker run -it --rm -v=${APP_DATA_DIR}:/opt/superset:rw $APP_IMG superset init
echo ""
@go.log INFO "Superset is now ready to be run, and be started with ./zeta command below!"



##########
# Provide instructions for next steps
echo ""
echo ""
echo "$APP_NAME instance ${APP_ID} installed at ${APP_HOME} and ready to go"
echo "To start please run: "
echo ""
echo "$ ./zeta package start ${APP_HOME}/$APP_ID.conf"
echo ""


