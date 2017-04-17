#!/bin/bash

###############
# $APP Specific
echo "The next step will walk through instance defaults for ${APP_ID}"
echo ""

read -e -p "Please enter the CPU shares to use with $APP_NAME: " -i "2.0" APP_CPU
echo ""
read -e -p "Please enter the Marathon Memory (MB) limit to use with $APP_NAME: " -i "2048" APP_MEM
echo ""

@go.log WARN "Some things you may want to consider: "
echo ""
@go.log WARN "1. You need a MySQL/MariaDB (Galera preferred for HA) Database to connect to"
@go.log WARN "2. There has been no testing done on Multiple Rancher Deployments on the same nodes - Don't test on Production Clusters!"
@go.log WARN "3. Have not figured out port 9345 and how to change that for Container HA"
@go.log WARN "4. Passwords for the Database server are stored in the marathon JSON this is not ideal."
echo ""
echo ""
@go.log WARN "We will now gather DB Information *to do offer to run DB install here*"
@go.log WARN "Warning: This information is not secured!"
read -e -p "Please enter the path to the conf file for your Galera Database: " -i "/zeta/$CLUSTERNAME/" APP_DB_CONF
if [ ! -f "$APP_DB_CONF" ]; then
    @go.log FATAL "Can't find conf at $APP_DB_CONF"
fi
echo ""
read -e -p "Enter the conf file for the HAProxy instance fronting your Galera cluster: " -i "/zeta/$CLUSTERNAME" APP_HA_CONF
if [ ! -f "$APP_HA_CONF" ]; then
    @go.log FATAL "Can't find conf at $APP_HA_CONF"
fi
echo ""

APP_CONF_DIR="$APP_HOME/conf"
mkdir -p $APP_CONF_DIR
sudo chown -R $IUSER:$IUSER $APP_CONF_DIR
sudo chmod -R 770 $APP_CONF_DIR




APP_HOSTNAME="${APP_ID}.${APP_ROLE}.marathon.slave.mesos"
DB_MAR_ID=$(cat $APP_DB_CONF|grep "MAR_ID"|cut -d"=" -f2|sed "s/\"//g")
DB_HOME=$(cat $APP_DB_CONF|grep "APP_HOME"|cut -d"=" -f2|sed "s/\"//g")
HA_MAR_ID=$(cat $APP_HA_CONF|grep "MAR_ID"|cut -d"=" -f2|sed "s/\"//g")
HA_HOME=$(cat $APP_HA_CONF|grep "APP_HOME"|cut -d"=" -f2|sed "s/\"//g")
HA_ENV=$(cat $APP_HA_CONF|grep "APP_ENV_FILE"|cut -d"=" -f2|sed "s/\"//g")

APP_DB_HOST=$(cat $HA_ENV|grep "HOST"|cut -d"=" -f2|sed "s/\"//g")
echo ""
read -e -p "Please confirm the DB Host: " -i "$APP_DB_HOST" APP_DB_HOST
echo ""
APP_DB_PORT=$(cat $HA_ENV|grep "WRT_PORT"|cut -d"=" -f2|sed "s/\"//g")
CUR_DB_HOST=$(./zeta cluster marathon getinfo "$DB_MAR_ID" "host" "$MARATHON_SUBMIT")
CUR_DB_CID=$(ssh $CUR_DB_HOST "sudo docker ps|grep galera|cut -d\" \" -f1")
echo ""
echo "Please enter the information for your MySQL/Maria/DB Cluster. Note: you will need the root password to be succesful!"
echo ""
read -e -p "Database DB Name for Rancher: " -i "cattle" APP_DB_NAME
echo ""
read -e -p "Datbase User for Rancher: " -i "cattle" APP_DB_USER
echo ""
read -e -p "Database Password for Rancher (will be echoed to screen!): " APP_DB_PASS
echo ""
echo "Do you want to issue a 'DROP DATABASE IF EXISTS' Statement prior to creation? - Use at your own risk"
read -e -p "Issue Drop statement? (Y/N): " -i "N" APP_DROP

if [ "$APP_DROP" == "Y" ]; then
    DB_DROP="DROP DATABASE IF EXISTS $APP_DB_NAME;"
else
    DB_DROP=""
fi

DB_ROOT=$(cat $DB_HOME/creds/db.sql|grep PASSWORD|cut -d"=" -f2|cut -d'"' -f2)

cat > $DB_HOME/creds/rancher.sql << EOLDB
$DB_DROP
CREATE DATABASE IF NOT EXISTS $APP_DB_NAME COLLATE = 'utf8_general_ci' CHARACTER SET = 'utf8';
GRANT ALL ON ${APP_DB_NAME}.* TO '${APP_DB_USER}'@'%' IDENTIFIED BY '${APP_DB_PASS}';
GRANT ALL ON ${APP_DB_NAME}.* TO '${APP_DB_USER}'@'localhost' IDENTIFIED BY '${APP_DB_PASS}';
SHOW DATABASES;
EOLDB

cat > $DB_HOME/creds/create_rancher.sh << EOLCRE
#!/bin/bash
mysql -u root -p$DB_ROOT mysql < /creds/rancher.sql
EOLCRE
chmod +x $DB_HOME/creds/create_rancher.sh
echo ""
@go.log WARN "Trying to Create DB $APP_DB_NAME on $APP_DB_HOST"
ssh $CUR_DB_HOST "sudo docker exec $CUR_DB_CID /creds/create_rancher.sh"
echo ""
read -e -p "I hope that worked for you, press enter to continue" GO_ON
echo ""

cat > $APP_CONF_DIR/db_conf.sh << EOLCONF
APP_DB_NAME="$APP_DB_NAME"
APP_DB_USER="$APP_DB_USER"
APP_DB_PASS="$APP_DB_PASS"
APP_DB_HOST="$APP_DB_HOST"
APP_DB_PORT="$APP_DB_PORT"
EOLCONF

SOME_COMMENTS="Main HTTP Port for Rancher Server"
PORTSTR="CLUSTER:tcp:30808:${APP_ROLE}:${APP_ID}:$SOME_COMMENTS"
getport "CHKADD" "$SOME_COMMENTS" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_HTTP_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_HTTP_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME $PSTR"
fi

bridgeports "APP_HTTP_PORT_JSON" "8080" "$APP_HTTP_PORTSTR"
haproxylabel "APP_HA_PROXY" "${APP_HTTP_PORTSTR}"
portslist "APP_PORT_LIST" "$APP_HTTP_PORTSTR"



APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"
cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_HTTP_PORT="${APP_HTTP_PORT}"
EOL1



APP_ARGS="\"args\":[\"--db-host\", \"$APP_DB_HOST\", \"--db-port\", \"$APP_DB_PORT\", \"--db-user\", \"$APP_DB_USER\", \"--db-pass\", \"$APP_DB_PASS\", \"--db-name\", \"$APP_DB_NAME\", \"--advertise-address\", \"$APP_HOSTNAME\", \"--advertise-http-port\", \"$APP_HTTP_PORT\" ]"

cat > $APP_MAR_FILE << EOL
{
  "id": "${APP_MAR_ID}",
  "cpus": $APP_CPU,
  "mem": $APP_MEM,
  $APP_ARGS,
  "instances": 1,
  "constraints": [["hostname", "UNIQUE"]],
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
        $APP_HTTP_PORT_JSON
      ]
    },
  "volumes": [
      {
        "containerPath": "/conf",
        "hostPath": "${APP_CONF_DIR}",
        "mode": "RW"
      }
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
