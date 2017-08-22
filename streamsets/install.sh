#!/bin/bash

###############
# $APP Specific
echo "The next step will walk through instance defaults for ${APP_ID}"
echo ""
read -e -p "Please enter the CPU shares to use with $APP_NAME: " -i "1.0" APP_CPU
echo ""
read -e -p "Please enter the Marathon Memory limit to use with $APP_NAME: " -i "1024" APP_MEM
echo ""
APP_MARATHON_MEM="$APP_MEM"
APP_MEM=$(($APP_MARATHON_MEM - 64))
@go.log WARN "Using $APP_MARATHON_MEM for Marathon and $APP_MEM for Java Heap"
echo ""
read -e -p "Please enter the user to run streamsets as: " -i "zetasvc${APP_ROLE}" APP_USER
echo ""
####################################################################################

# The port listening in the container
APP_CONT_PORT="18630"

PORTSTR="CLUSTER:tcp:28630:${APP_ROLE}:${APP_ID}:Port for Stream sets $APP_ID"
getport "CHKADD" "SSL port" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME instance $APP_ID with $PSTR"
fi
bridgeports "APP_PORT_JSON" "$APP_CONT_PORT" "$APP_PORTSTR"

haproxylabel "APP_HA_PROXY" "${APP_PORTSTR}"
portslist "APP_PORT_LIST" "$APP_PORTSTR"

####################################################################################

APP_SUB=$(echo "$APP_MAR_ID"|sed "s@/@ @g")
APP_OUT=$(echo "$APP_SUB"| sed 's/ /\n/g' | tac | sed ':a; $!{N;ba};s/\n/ /g'|tr " " "-")

CN_GUESS="${APP_OUT}.marathon.slave.mesos"
APP_API_URL="https://${CN_GUESS}:$APP_PORT"

APP_MAR_FILE="${APP_HOME}/marathon.json"
APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"


SDC_DIST="/opt/streamsets/streamsets-datacollector-${APP_VER}"

####################################################################################

APP_CONF_DIR="$APP_HOME/conf"
APP_LOG_DIR="$APP_HOME/logs"
APP_SBIN_DIR="$APP_HOME/sbin"
APP_DATA_DIR="$APP_HOME/data"
APP_RESOURCE_DIR="$APP_HOME/resources"
APP_CERT_LOC="$APP_HOME/certs"

mkdir -p $APP_CONF_DIR
sudo chown -R $APP_USER:$IUSER $APP_CONF_DIR
sudo chmod 770 $APP_CONF_DIR

mkdir -p $APP_LOG_DIR
sudo chown -R $IUSER:zeta${APP_ROLE}data $APP_LOG_DIR
sudo chmod 770 $APP_LOG_DIR
sudo chmod g+s $APP_LOG_DIR

mkdir -p $APP_SBIN_DIR
sudo chown -R $IUSER:$IUSER $APP_SBIN_DIR
sudo chmod 770 $APP_SBIN_DIR

mkdir -p $APP_RESOURCE_DIR
sudo chown -R $IUSER:zeta${APP_ROLE}data $APP_RESOURCE_DIR
sudo chmod 770 $APP_RESOURCE_DIR
sudo chmod g+s $APP_RESOURCE_DIR

mkdir -p $APP_DATA_DIR
sudo chown -R $IUSER:zeta${APP_ROLE}data $APP_DATA_DIR
sudo chmod 770 $APP_DATA_DIR
sudo chmod g+s $APP_DATA_DIR

mkdir -p $APP_CERT_LOC
sudo chown -R $APP_USER:$IUSER $APP_CERT_LOC
sudo chmod 770 $APP_CERT_LOC

####################################################################################

@go.log WARN "Running $APP_IMG to generate configs for things"

sudo docker run -it --rm -v=$APP_CONF_DIR:/app/conf:rw $APP_IMG cp -R /opt/streamsets/streamsets-datacollector-${APP_VER}/etc /app/conf/
sudo docker run -it --rm -v=$APP_CONF_DIR:/app/conf:rw $APP_IMG cp -R /opt/streamsets/streamsets-datacollector-${APP_VER}/libexec /app/conf/
sudo mv $APP_CONF_DIR/etc/* $APP_CONF_DIR
sudo cp $APP_CONF_DIR/libexec/sdc-env.sh $APP_CONF_DIR/
sudo cp $APP_CONF_DIR/libexec/sdcd-env.sh $APP_CONF_DIR/

# test for some failure we don't want /etc removed"
RMDIR="$APP_CONF_DIR/etc"
RMDIR2="$APP_CONF_DIR/libexec"
if [ "$RMDIR" == "/etc" ] || [ "$RMDIR2" == "/libexec" ]; then
    @go.log FATAL "Something happened, but I won't sudo rm /etc or /libexeccause I am good like that"
fi

sudo rm -rf $RMDIR
sudo rm -rf $RMDIR2
sudo chown -R $APP_USER:$IUSER $APP_CONF_DIR
sudo chmod -R 770 $APP_CONF_DIR


####################################################################################
@go.log WARN "Generating Cert"
# Doing Java for this app because Streamsets uses Java
. $CLUSTERMOUNT/zeta/shared/zetaca/gen_java_keystore.sh
. $APP_CERT_LOC/capass

####################################################################################
# Update the default conf file to handle SSL, etc
@go.log WARN "Updating Config settings"

APP_SDC_CONF="$APP_CONF_DIR/sdc.properties"


# First we disable the http port - HTTPS ONLY!
@go.log INFO "Disabling HTTP"
sed -r -i "s/^http\.port=.*/http.port=-1/g" $APP_SDC_CONF

# Set the https port to be the container port
@go.log INFO "Setting container HTTPS port"
sed -r -i "s/^https.port=.*/https.port=$APP_CONT_PORT/g" $APP_SDC_CONF

# Set the base URL for Emails and such
@go.log INFO "Setting base URL"
sed -r -i "s@#sdc\.base\.http\.url=.*@sdc.base.http.url=$APP_API_URL@g" $APP_SDC_CONF

# Moving certs to conf folder per whatever it having to be in etc I guess
@go.log INFO "Moving Keystore"
mv $APP_CERT_LOC/myKeyStore.jks $APP_CONF_DIR/keystore.jks
echo -n "$KEYSTOREPASS" > $APP_CONF_DIR/keystore-password.txt

# Setting up the trust store
@go.log INFO "Setting up truststore"
sed -r -i "s@#https\.truststore\.path=.*@https.truststore.path=/app/certs/myTrustStore.jts@g" $APP_SDC_CONF

# Hard coded truststore path I guess
@go.log INFO "Setting Truststore password"
sed -r -i "s/#https\.truststore\.password=.*/https.truststore.password=${TRUSTSTOREPASS}/g" $APP_SDC_CONF

@go.log INFO "Setting Basic auth"
# Changing from form to basic auth for easier automation if needed
sed -r -i "s/http\.authentication=form/http.authentication=basic/g" $APP_SDC_CONF

# Setup LDAP Auth
@go.log INFO "Setting LDAP as Auth Mech"
sed -r -i "s/http\.authentication\.login\.module=.*/http.authentication.login.module=ldap/g" $APP_SDC_CONF

#
APP_LDAP_CONF="$APP_CONF_DIR/ldap-login.conf"
LDAP_HOST=$(echo "$LDAP_URL"|sed "s@ldap://@@g")

@go.log INFO "Setting LDAP INFO"
# Set the LDAP Host
sed -r -i "s/hostname=.*/hostname=\"$LDAP_HOST\"/g" $APP_LDAP_CONF

# Let the Bind DN
sed -r -i "s/bindDn=.*/bindDn=\"$LDAP_RO_USER\"/g" $APP_LDAP_CONF
# Set a Bind DN Password
sed -r -i "s/bindPassword=.*/bindPassword=\"$LDAP_RO_PASS\"/g" $APP_LDAP_CONF

# Force Binding Password
sed -r -i "s/forceBindingLogin=.*/forceBindingLogin=\"true\"/g" $APP_LDAP_CONF

# Set base user search
sed -r -i "s/userBaseDn=.*/userBaseDn=\"dc=marathon,dc=mesos\"/g" $APP_LDAP_CONF

# Set user id val (Default is uid, we are going with cn)
sed -r -i "s/userIdAttribute=.*/userIdAttribute=\"cn\"/g" $APP_LDAP_CONF

# Set the user password val
sed -r -i "s/userPasswordAttribute=.*/userPasswordAttribute=\"Password\"/g" $APP_LDAP_CONF

# Set the filter
sed -r -i "s/userFilter=.*/userFilter=\"cn={user}\"/g" $APP_LDAP_CONF

# Group base, we set this to be app groups only at first, you can open it up if need be

sed -r -i "s/roleBaseDn=.*/roleBaseDn=\"ou=groups,ou=zeta${APP_ROLE},dc=marathon,dc=mesos\"/g" $APP_LDAP_CONF

sed -r -i "s/roleMemberAttribute=.*/roleMemberAttribute=\"memberUid\"/g" $APP_LDAP_CONF

sed -r -i "s/roleObjectClass=.*/roleObjectClass=\"posixGroup\"/g" $APP_LDAP_CONF

sed -r -i "s/roleFilter=.*/roleFilter=\"memberUid={user}\";/g" $APP_LDAP_CONF


@go.log INFO "Copying mapr.login.conf to ldap-login.conf"
cat /opt/mapr/conf/mapr.login.conf >> $APP_LDAP_CONF

# Update Mapping of LDAP groups
# We default to zeta$ROLEdata being creator, zeta$ROLEzeta being manager, zeta$ROLEetl being admin and zeta$ROLEapps being guest
sed -r -i "s/http\.authentication\.ldap\.role\.mapping=.*/http.authentication.ldap.role.mapping=zeta${APP_ROLE}etl:admin,zeta${APP_ROLE}data:creator,zeta${APP_ROLE}zeta:manager,zeta${APP_ROLE}apps:guest/g" $APP_SDC_CONF

sudo chown -R $APP_USER:$IUSER $APP_CONF_DIR
sudo chmod -R 770 $APP_CONF_DIR


# Update the memory in the sdc-env.sh

sed -r -i "s/-Xmx1024m/-Xmx${APP_MEM}m/g" $APP_CONF_DIR/sdc-env.sh
sed -r -i "s/-Xms1024m/-Xms${APP_MEM}m/g" $APP_CONF_DIR/sdc-env.sh

####################################################################################

cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_HOST="${APP_HOSTNAME}"
export ZETA_${APP_NAME}_${APP_ID}_PORT="${APP_PORT}"
EOL1


####################################################################################

cat > $APP_SBIN_DIR/start.sh << EOS
#!/bin/bash
echo "Copying over ENV Info"
cp /app/conf/sdc-env.sh $SDC_DIST/libexec/
cp /app/conf/sdcd-env.sh $SDC_DIST/libexec/

echo "Setting up MapR"
$SDC_DIST/bin/streamsets setup-mapr

echo "Starting Stream Sets"
su -c "$SDC_DIST/bin/streamsets dc" $APP_USER
EOS
chown $IUSER:$IUSER $APP_SBIN_DIR/start.sh
chmod +x $APP_SBIN_DIR/start.sh

####################################################################################

cat > $APP_MAR_FILE << EOL
{
  "id": "${APP_MAR_ID}",
  "cmd": "/app/sbin/start.sh",
  "cpus": ${APP_CPU},
  "mem": ${APP_MARATHON_MEM},
  "instances": 1,
  "env": {
    "MAPR_HOME": "/opt/mapr",
    "MAPR_VERSION": "5.2.0",
    "SDC_RESOURCES": "/app/resources",
    "SDC_DATA": "/app/data",
    "SDC_CONF": "/app/conf",
    "SDC_LOG": "/app/logs",
    "SDC_HOME": "$SDC_DIST",
    "SDC_DIST": "$SDC_DIST"
  },
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
      { "containerPath": "/app/conf", "hostPath": "${APP_CONF_DIR}", "mode": "RW" },
      { "containerPath": "/app/data", "hostPath": "${APP_DATA_DIR}", "mode": "RW" },
      { "containerPath": "/app/logs", "hostPath": "${APP_LOG_DIR}", "mode": "RW" },
      { "containerPath": "/app/resources", "hostPath": "${APP_RESOURCE_DIR}", "mode": "RW" },
      { "containerPath": "/app/sbin", "hostPath": "${APP_SBIN_DIR}", "mode": "RO" },
      { "containerPath": "/opt/mapr", "hostPath": "/opt/mapr", "mode": "RO" },
      { "containerPath": "/app/certs", "hostPath": "${APP_CERT_LOC}", "mode": "RO" },
      { "containerPath": "/zeta", "hostPath": "/zeta", "mode": "RW" },
      { "containerPath": "/app/logs", "hostPath": "${APP_LOG_DIR}", "mode": "RW" }
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


