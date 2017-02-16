#!/bin/bash

###############
# $APP Specific
echo "The next step will walk through instance defaults for ${APP_ID}"
echo ""
read -e -p "Please enter the CPU shares to use with $APP_NAME: " -i "1.0" APP_CPU
echo ""
read -e -p "Please enter the Marathon Memory limit to use with cortex: " -i "2048" APP_MEM
echo ""
read -e -p "How many instances of $APP_NAME do you wish to run: " -i "1" APP_CNT
echo ""
read -e -p "What user should we run thehive as: " -i "zetasvc${APP_ROLE}" APP_USER
echo ""

echo "The hive can use ldap auth, it's just not working quite yet. Defaulting to local auth"
echo ""
#echo "The hive can use ldap authentication, do you wish to use cluster ldap auth?"
#read -e -p "Use Cluster LDAP Auth? (Y/N): " -i "Y" APP_LDAP
#if [ "$APP_LDAP" == "Y" ]; then
#    APP_AUTH_TYPE="type = [local,ldap]"
#    read -e -p "Please enter the group to create under OU zeta${APP_ROLE}/groups for hive users on this instance: " -i "hive_${APP_ID}_users" APP_GROUP
#    @go.log INFO "Adding Group $APP_GROUP"
#    ./zeta users group -a -r="${APP_ROLE}" -g="$APP_GROUP" -D="Access to thehive instance $APP_ID in role $APP_ROLE" -u
#else
#    APP_AUTH_TYPE="type = [local]"
#fi
APP_AUTH_TYPE="type = [local]"

echo "Thehive Cortex allows for lookups on multiple api services.  You should have a cortex server. If you don't yet, you can install one here"
echo ""
read -e -p "Do you wish to install a new Cortex instance for thehive? (Y/N): " -i "Y" APP_CORTEX_INSTALL
echo ""
if [ "$APP_CORTEX_INSTALL" == "Y" ]; then
    @go.log INFO "Installing thehive Cortex"
    ./zeta package install thehivecortex
    sleep 1
    read -e -p "Please enter path to the installed instance of thehive Cortex: " APP_CORTEX_CONF
    ./zeta package start $APP_CORTEX_CONF
else
    echo "Not installing a new cortex, please provide a URL to the existing instance"
fi

read -e -p "What is the URL for the Cortex instance to use with the hive? " APP_CORTEX
echo "The Hive needs an elastic search instance. You can install one here, or use an existing instance"
read -e -p "Do you wish to install a new instance of Elastic Search for thehive? (Y/N): " -i "Y" APP_ES_INSTALL

if [ "$APP_ES_INSTALL" == "Y" ]; then
    @go.log INFO "Running Elastic Search Install"
    ./zeta package install elasticsearch
    read -e -p "Enter the path to your newly installed ES Instance conf file: " APP_ES_CONF
    if [ ! -f "$APP_ES_CONF" ]; then
        @go.log FATAL "ES Conf does not exist"
    fi
else
    read -e -p "Enter the path to your ES instance conf file: " APP_ES_CONF
    if [ ! -f "$APP_ES_CONF" ]; then
        @go.log FATAL "ES Conf does not exist - Exiting"
    fi
fi
echo "Filling Vars"
ES_HOME=$(cat $APP_ES_CONF|grep APP_HOME|sed "s/APP_HOME=//g"|sed "s/\"//g")
ES_CLUSTERNAME=$(cat $ES_HOME/conf/elasticsearch.yml|grep "cluster\.name"|cut -d":" -f2|sed "s/\"//g"|sed "s/ \+//g")
ES_TCPPORT=$(cat $ES_HOME/conf/elasticsearch.yml|grep "transport\.tcp\.port"|cut -d":" -f2|sed "s/ \+//g")
ES_NODES=$(cat $ES_HOME/conf/elasticsearch.yml|grep "discovery\.zen\.ping\.unicast\.hosts"|cut -d":" -f2|sed "s/\"//g"|sed "s/ \+//g"|tr "," " ")
ES_CONF_NODES=""

for N in $ES_NODES; do
    if [ "$ES_CONF_NODES" == "" ]; then
        ES_CONF_NODES="[\"${N}:${ES_TCPPORT}\""
    else
        ES_CONF_NODES="${ES_CONF_NODES}, \"${N}:${ES_TCPPORT}\""
    fi
done
ES_CONF_NODES="${ES_CONF_NODES}]"

ES_TEST=$(cat $ES_HOME/conf/elasticsearch.yml|grep "script\.inline")

echo ""
echo "Elasticsearch Instance Details:"
echo "-------------------------------"
echo "ES_HOME: $ES_HOME"
echo "ES_CLUSTERNAME: $ES_CLUSTERNAME"
echo "ES_TCPPORT: $ES_TCPPORT"
echo "ES_NODES: $ES_NODES"
echo "ES_CONF_NODES: $ES_CONF_NODES"
echo "ES_TEST: $ES_TEST"
echo "-------------------------------"
read -e -p "Does this look correct? (Y/N): " -i "Y" ES_CHK
echo ""

if [ "$ES_CHK" != "Y" ]; then
    @go.log FATAL "Quitting per user"
fi



if [ "$ES_TEST" == "" ]; then
    @go.log WARN "It appears that settings required for the hive are not included with your Elastic search instance. Should we add and restart your service?"
    read -e -p "Add settings to elastic search regarding queues and scripts (required for the hive) (Y/N): " -i "Y" UPDATE_ES
    if [ "$UPDATE_ES" == "Y" ]; then
        @go.log INFO "Going to stop the ES instance (if it's already stopped, it will generate warning, no worries!"
        ./zeta package stop $APP_ES_CONF
        echo "script.inline: on" >> $ES_HOME/conf/elasticsearch.yml
        echo "threadpool.index.queue_size: 100000" >> $ES_HOME/conf/elasticsearch.yml
        echo "threadpool.search.queue_size: 100000" >> $ES_HOME/conf/elasticsearch.yml
        echo "threadpool.bulk.queue_size: 1000" >> $ES_HOME/conf/elasticsearch.yml
        @go.log INFO "Starting Elastic Search"
        ./zeta package start $APP_ES_CONF
    else
        @go.log WARN "It is likely you will run into issues with your Elastic Search setup if you don't manually add the following lines to your elasticsearch.yml and restart your instance"
        echo "script.inline: on"
        echo "threadpool.index.queue_size: 100000"
        echo "threadpool.search.queue_size: 100000"
        echo "threadpool.bulk.queue_size: 1000"
    fi

fi

echo "We can generate a secret key, or you can enter one, this will be stored in application.conf"
echo ""
read -e -p "Generate secret key? (Answering N will prompt for a secret key (Y/N): " -i "Y" APP_GEN_KEY

echo ""
if [ "$APP_GEN_KEY" != "Y" ]; then
    read -e -p "Secret Key for Cortext (will be echoed to the screen): " APP_SECRET
else
    APP_SECRET=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1)
fi

PORTSTR="CLUSTER:tcp:30943:${APP_ROLE}:${APP_ID}:HTTPS Port for TheHive"
getport "CHKADD" "HTTPS Port for theHive" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME instance $APP_ID with $PSTR"
fi


bridgeports "APP_PORT_JSON" "$APP_PORT" "$APP_PORTSTR"
haproxylabel "APP_HA_PROXY" "${APP_PORTSTR}"

APP_MAR_FILE="${APP_HOME}/marathon.json"
APP_CERT_LOC="$APP_HOME/certs"
APP_CONF_DIR="$APP_HOME/conf"
APP_LOG_DIR="$APP_HOME/logs"
APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"
CN_GUESS="${APP_ID}-${APP_ROLE}.marathon.slave.mesos"
mkdir -p $APP_CONF_DIR
mkdir -p $APP_LOG_DIR
mkdir -p $APP_CERT_LOC
sudo chown -R $APP_USER:$IUSER $APP_CONF_DIR
sudo chown -R $APP_USER:$IUSER $APP_LOG_DIR
sudo chown -R $APP_USER:$IUSER $APP_CERT_LOC
sudo chmod 770 $APP_CONF_DIR
sudo chmod 770 $APP_LOG_DIR
sudo chmod 770 $APP_CERT_LOC

# Doing Java for this app because PLAY uses Java
. $CLUSTERMOUNT/zeta/shared/zetaca/gen_java_keystore.sh

cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_PORT="${APP_PORT}"
EOL1

cat > $APP_CONF_DIR/application.conf  << EOL2
# Register module for dependency injection
play.modules.enabled += global.TheHive
play.modules.enabled += connectors.cortex.CortexConnector
# handler for requests (check if database is in maintenance or not)
#play.http.requestHandler = TheHiveHostRequestHandler
play.crypto.secret="$APP_SECRET"
play.http.filters = global.TheHiveFilters
http.port: disabled
https.port: ${APP_PORT}
play.server.https.keyStore {
    path: "/opt/thehive/certs/myKeyStore.jks"
    type: "JKS"
    password: "${KEYSTOREPASS}"
}

# Max textual content length
play.http.parser.maxMemoryBuffer=1M
# Max file size
play.http.parser.maxDiskBuffer=512M

# ElasticSearch
search {
  # Name of the index
  index = the_hive
  # Name of the ElasticSearch cluster
  cluster = $ES_CLUSTERNAME
  # Address of the ElasticSearch instance
  host = $ES_CONF_NODES
  # Scroll keepalive
  keepalive = 1m
  # Size of the page for scroll
  pagesize = 50
}

# Datastore
datastore {
  name = data
  # Size of stored data chunks
  chunksize = 50k
  hash {
    # Main hash algorithm /!\ Don't change this value
    main = "SHA-256"
    # Additional hash algorithms (used in attachments)
    extra = ["SHA-1", "MD5"]
  }
  attachment.password = "malware"
}

auth {
    # "type" parameter contains authentication provider. It can be multi-valued (useful for migration)
    # available auth types are:
    # services.LocalAuthSrv : passwords are stored in user entity (in ElasticSearch). No configuration are required.
    # ad : use ActiveDirectory to authenticate users. Configuration is under "auth.ad" key
    # ldap : use LDAP to authenticate users. Configuration is under "auth.ldap" key
    $APP_AUTH_TYPE

    ad {
        # Domain Windows name using DNS format. This parameter is required.
        #domainFQDN = "mydomain.local"

        # Domain Windows name using short format. This parameter is required.
        #domainName = "MYDOMAIN"

        # Use SSL to connect to domain controller
        #useSSL = true
    }

    ldap {
        # LDAP server name or address. Port can be specified (host:port). This parameter is required.
        serverName = "openldap-shared.marathon.slave.mesos:389"
        # Use SSL to connect to directory server
        #useSSL = true

        # Account to use to bind on LDAP server. This parameter is required.
        bindDN = "cn=readonly,dc=marathon,dc=mesos"

        # Password of the binding account. This parameter is required.
        bindPW = "readonly"

        # Base DN to search users. This parameter is required.
        baseDN = "dc=marathon,dc=mesos"

        # Filter to search user {0} is replaced by user name. This parameter is required.
        #filter = "(cn={0})"
        #APPGROUP=${APP_GROUP}
        filter = "(&(objectClass=posixAccount)(memberof=cn=${APP_GROUP},ou=groups,ou=zeta${APP_ROLE},dc=marathon,dc=mesos)(cn={0}))"
    }
}

# Maximum time between two requests without requesting authentication
session {
  warning = 5m
  inactivity = 1h
}

# Streaming
stream.longpolling {
  # Maximum time a stream request waits for new element
  refresh = 1m
  # Lifetime of the stream session without request
  cache = 15m
  nextItemMaxWait = 500ms
  globalMaxWait = 1s
}

# Name of the ElasticSearch type used to store dblist /!\ Don't change this value
dblist.name = dblist
# Name of the ElasticSearch type used to store audit event /!\ Don't change this value
audit.name = audit
# Name of the ElasticSearch type used to store attachment /!\ Don't change this value
datastore.name = data

# Cortex configuration
########

cortex {
  "CORTEXSRV" {
    # URL of MISP server
    url = "$APP_CORTEX"
  }
}

# MISP configuration
########

misp {
  #"MISP-SERVER-ID" {
  #  # URL of MISP server
  #  url = ""
  #  # authentication key
  #  key = ""
  #  #tags to be added to imported artifact
  #  tags = ["misp"]
  #}

  # truststore to used to validate MISP certificate (if default truststore is not suffisient)
  #cert = /path/to/truststore.jsk

  # Interval between two MISP event import
  interval = 1h
}

# Metrics configuration
########

metrics {
  name = default
  enabled = false
  rateUnit = SECONDS
  durationUnit = SECONDS
  jvm = true
  logback = true

  graphite {
    enabled = false
    host = "127.0.0.1"
    port = 2003
    prefix = thehive
    rateUnit = SECONDS
    durationUnit = MILLISECONDS
    period = 10s
  }

  ganglia {
    enabled = false
    host = "127.0.0.1"
    port = 8649
    mode = UNICAST
    ttl = 1
    version = 3.1
    prefix = thehive
    rateUnit = SECONDS
    durationUnit = MILLISECONDS
    tmax = 60
    dmax = 0
    period = 10s
  }

  influx {
    enabled = false
    url = "http://127.0.0.1:8086"
    user = root
    password = root
    database = thehive
    retention = default
    consistency = ALL
    #tags = {
    #   tag1 = value1
    #   tag2 = value2
    #}
    period = 10s
  }
}
EOL2



cat > $APP_CONF_DIR/run.sh << EOL3
#!/bin/bash
cd /opt/thehive/thehive
bin/thehive -Dconfig.file=/opt/thehive/etc/application.conf -Djavax.net.ssl.trustStore=/opt/thehive/certs/myTrustStore.jts -Djavax.net.ssl.trustStorePassword="${TRUSTSTOREPASS}"



EOL3
chmod +x $APP_CONF_DIR/run.sh

cat > $APP_MAR_FILE << EOL
{
  "id": "${APP_MAR_ID}",
  "cmd": "chown -R ${APP_USER}:${IUSER} /opt/thehive && su -c /opt/thehive/etc/run.sh ${APP_USER}",
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
      { "containerPath": "/opt/thehive/etc", "hostPath": "${APP_CONF_DIR}", "mode": "RW" },
      { "containerPath": "/opt/thehive/thehive/logs", "hostPath": "${APP_LOG_DIR}", "mode": "RW" },
      { "containerPath": "/opt/thehive/certs", "hostPath": "${APP_CERT_LOC}", "mode":"RW"}
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


