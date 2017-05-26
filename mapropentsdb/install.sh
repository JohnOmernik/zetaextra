#!/bin/bash

# Add the Lib for the Filesystem
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
#read -e -p "How many instances of $APP_NAME do you wish to run: " -i "1" APP_CNT
APP_CNT=1 #
echo ""
read -e -p "What user should we run $APP_NAME as: " -i "zetasvc${APP_ROLE}" APP_USER
echo ""

PORTSTR="CLUSTER:tcp:30424:${APP_ROLE}:${APP_ID}:Network Port for $APP_NAME"
getport "CHKADD" "Network Port for $APP_NAME" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME instance $APP_ID with $PSTR"
fi

bridgeports "APP_PORT_JSON" "$APP_PORT" "$APP_PORTSTR"
haproxylabel "APP_HA_PROXY" "${APP_PORTSTR}"
portslist "APP_PORT_LIST" "${APP_PORTSTR}"

APP_MAR_FILE="${APP_HOME}/marathon.json"
APP_CONF_DIR="$APP_HOME/conf"
APP_PLUGIN_DIR="$APP_HOME/plugins"

APP_LOG_DIR="$APP_HOME/logs"
APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"


APP_SUB=$(echo "$APP_MAR_ID"|sed "s@/@ @g")
APP_OUT=$(echo "$APP_SUB"| sed 's/ /\n/g' | tac | sed ':a; $!{N;ba};s/\n/ /g'|tr " " "-")

APP_API_URL="http://${APP_OUT}.marathon.slave.mesos:$APP_PORT"


@go.log INFO "Adding Volume for Tables"
APP_TABLE_DIR="$APP_HOME/tables"
VOL="${APP_DIR}.${APP_ROLE}.${APP_ID}.tables"
fs_mkvol "RETCODE" "$APP_TABLE_DIR" "$VOL" "775"
sudo chown ${APP_USER}:${IUSER} $APP_TABLE_DIR
sudo chmod 770 $APP_TABLE_DIR

@go.log INFO "Creating MapR-DB Tables for use in OpenTSDB"
echo ""
echo @go.log INFO "Creating Data Table"

MAPRCLI="./zeta fs mapr maprcli -U=mapr"

NFSBASE="/zeta/$CLUSTERNAME"

APP_TABLE_HDFS=$(echo "$APP_HOME"|sed "s@$NFSBASE@@")
APP_TABLE_HDFS="${APP_TABLE_HDFS}/tables"

TABLES_PATH="$APP_TABLE_HDFS"

TSDB_TABLE="$TABLES_PATH/tsdb"
UID_TABLE="$TABLES_PATH/tsdb-uid"
TREE_TABLE="$TABLES_PATH/tsdb-tree"
META_TABLE="$TABLES_PATH/tsdb-meta"


@go.log INFO "Creating $TSDB_TABLE table..."
$MAPRCLI table create -path $TSDB_TABLE -defaultreadperm "\(u:mapr\|u:${APP_USER}\|u:zetaadm\)" -defaultwriteperm "\(u:mapr\|u:${APP_USER}\|u:zetaadm\)" -defaultappendperm "\(u:mapr\|u:${APP_USER}\|u:zetaadm\)"
$MAPRCLI table cf create -path $TSDB_TABLE -cfname t -maxversions 1 -inmemory false -compression lzf -ttl 0

@go.log INFO  "Creating $UID_TABLE table..."
$MAPRCLI table create -path $UID_TABLE -defaultreadperm "\(u:mapr\|u:${APP_USER}\|u:zetaadm\)" -defaultwriteperm "\(u:mapr\|u:${APP_USER}\|u:zetaadm\)" -defaultappendperm "\(u:mapr\|u:${APP_USER}\|u:zetaadm\)"
$MAPRCLI table cf create -path $UID_TABLE -cfname id -maxversions 1 -inmemory true -compression lzf -ttl 0
$MAPRCLI table cf create -path $UID_TABLE -cfname name -maxversions 1 -inmemory true -compression lzf -ttl 0

@go.log INFO "Creating $TREE_TABLE table..."
$MAPRCLI table create -path $TREE_TABLE -defaultreadperm "\(u:mapr\|u:${APP_USER}\|u:zetaadm\)" -defaultwriteperm "\(u:mapr\|u:${APP_USER}\|u:zetaadm\)" -defaultappendperm "\(u:mapr\|u:${APP_USER}\|u:zetaadm\)"
$MAPRCLI table cf create -path $TREE_TABLE -cfname t -maxversions 1 -inmemory false -compression lzf -ttl 0

@go.log INFO "Creating $META_TABLE table..."
$MAPRCLI table create -path $META_TABLE -defaultreadperm "\(u:mapr\|u:${APP_USER}\|u:zetaadm\)" -defaultwriteperm "\(u:mapr\|u:${APP_USER}\|u:zetaadm\)" -defaultappendperm "\(u:mapr\|u:${APP_USER}\|u:zetaadm\)"
$MAPRCLI table cf create -path $META_TABLE -cfname name -maxversions 1 -inmemory false -compression lzf -ttl 0

mkdir -p $APP_CONF_DIR
mkdir -p $APP_LOG_DIR
mkdir -p $APP_PLUGIN_DIR
sudo chown -R $APP_USER:$IUSER $APP_CONF_DIR
sudo chown -R $APP_USER:$IUSER $APP_LOG_DIR
sudo chown -R $APP_USER:$IUSER $APP_PLUGIN_DIR
sudo chmod 770 $APP_CONF_DIR
sudo chmod 770 $APP_LOG_DIR
sudo chmod 770 $APP_PLUGIN_DIR

cat > $APP_CONF_DIR/opentsdb.conf << EOF
# --------- NETWORK ----------
# The TCP port TSD should use for communications
# *** REQUIRED ***
tsd.network.port = $APP_PORT

# The IPv4 network address to bind to, defaults to all addresses
# tsd.network.bind = 0.0.0.0

# Disable Nagel's algorithm.  Default is True
#tsd.network.tcp_no_delay = true

# Determines whether or not to send keepalive packets to peers, default
# is True
#tsd.network.keep_alive = true

# Determines if the same socket should be used for new connections, default
# is True
#tsd.network.reuse_address = true

# Set the domains that OpenTSDB will allow CORS from. (This could be your Grafana Domain for example)
tsd.http.request.cors_domains = *

# Number of worker threads dedicated to Netty, defaults to # of CPUs * 2
#tsd.network.worker_threads = 8

# Whether or not to use NIO or tradditional blocking IO, defaults to True
#tsd.network.async_io = true

# ----------- HTTP -----------
# The location of static files for the HTTP GUI interface.
# *** REQUIRED ***
tsd.http.staticroot = /usr/share/opentsdb/static/

# Where TSD should write it's cache files to
# *** REQUIRED ***
tsd.http.cachedir = /tmp/opentsdb

# Enable Chunked request to HTTP API
tsd.http.request.enable_chunked = true
# --------- CORE ----------
# Whether or not to automatically create UIDs for new metric types, default
# is False
#tsd.core.auto_create_metrics = false

# Full path to a directory containing plugins for OpenTSDB
tsd.core.plugin_path = /usr/share/opentsdb/plugins

# --------- STORAGE ----------
# Whether or not to enable data compaction in HBase, default is True
#tsd.storage.enable_compaction = true

# How often, in milliseconds, to flush the data point queue to storage, 
# default is 1,000
# tsd.storage.flush_interval = 1000

# tsd storage
tsd.storage.hbase.data_table = $TSDB_TABLE
tsd.storage.hbase.uid_table = $UID_TABLE
tsd.storage.hbase.meta_table = $META_TABLE
tsd.storage.hbase.tree_table = $TREE_TABLE


# A comma separated list of Zookeeper hosts to connect to, with or without 
# port specifiers, default is "localhost"
#tsd.storage.hbase.zk_quorum = localhost

# ONLY set this to true for testing purposes, NEVER in production
tsd.core.auto_create_metrics = true

# MapR-DB does not utilize this value, but it must be set to something
tsd.storage.hbase.zk_quorum = localhost:5181

EOF

cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_PORT="${APP_PORT}"
EOL1


cat > $APP_CONF_DIR/logback.xml << EOB
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <!--<jmxConfigurator/>-->
  <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
    <encoder>
      <pattern>
        %d{ISO8601} %-5level [%thread] %logger{0}: %msg%n
      </pattern>
    </encoder>
  </appender>

  <!-- This appender is responsible for the /logs endpoint. It maintains MaxSize 
       lines of the log file in memory. If you don't need the endpoint, disable
       this appender (by removing the line "<appender-ref ref="CYCLIC"/>" in
       the "root" section below) to save some cycles and memory. -->
  <appender name="CYCLIC" class="ch.qos.logback.core.read.CyclicBufferAppender">
    <MaxSize>1024</MaxSize>
  </appender>

  <!-- Appender to write OpenTSDB data to a set of rotating log files -->
  <appender name="FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
    <file>/var/log/opentsdb/opentsdb.log</file>
    <append>true</append>

    <rollingPolicy class="ch.qos.logback.core.rolling.FixedWindowRollingPolicy">
      <fileNamePattern>/var/log/opentsdb/opentsdb.log.%i</fileNamePattern>
      <minIndex>1</minIndex>
      <maxIndex>3</maxIndex>
    </rollingPolicy>

    <triggeringPolicy class="ch.qos.logback.core.rolling.SizeBasedTriggeringPolicy">
      <maxFileSize>128MB</maxFileSize>
    </triggeringPolicy>

    <encoder>
      <pattern>%d{HH:mm:ss.SSS} %-5level [%logger{0}.%M] - %msg%n</pattern>
    </encoder>
  </appender>

  <!-- Appender for writing full and completed queries to a log file. To use it, make
       sure to set the "level" to "INFO" in QueryLog below. -->
  <appender name="QUERY_LOG" class="ch.qos.logback.core.rolling.RollingFileAppender">
    <file>/var/log/opentsdb/queries.log</file>
    <append>true</append>

    <rollingPolicy class="ch.qos.logback.core.rolling.FixedWindowRollingPolicy">
        <fileNamePattern>/var/log/opentsdb/queries.log.%i</fileNamePattern>
        <minIndex>1</minIndex>
        <maxIndex>4</maxIndex>
    </rollingPolicy>

    <triggeringPolicy class="ch.qos.logback.core.rolling.SizeBasedTriggeringPolicy">
        <maxFileSize>128MB</maxFileSize>
    </triggeringPolicy>
    <encoder>
        <pattern>%date{ISO8601} [%logger.%M] %msg%n</pattern>
    </encoder>
  </appender>

  <!-- Per class logger levels -->
  <logger name="QueryLog" level="OFF" additivity="false">
    <appender-ref ref="QUERY_LOG"/>
  </logger>
  <logger name="org.apache.zookeeper" level="INFO"/>
  <logger name="org.hbase.async" level="INFO"/>
  <logger name="com.stumbleupon.async" level="INFO"/>

  <!-- Fallthrough root logger and router -->
  <root level="INFO">
    <!-- <appender-ref ref="STDOUT"/> -->
    <appender-ref ref="CYCLIC"/>
    <appender-ref ref="FILE"/>
  </root>
</configuration>

EOB
cat > $APP_CONF_DIR/run.sh << EOC
#!/bin/bash
ulimit -n 65535
/usr/share/opentsdb/bin/tsdb tsd

EOC

sudo chmod +x $APP_CONF_DIR/run.sh


cat > $APP_MAR_FILE << EOL
{
  "id": "${APP_MAR_ID}",
  "cmd": "mkdir -p /tmp/opentsdb && chown -R ${APP_USER}:${IUSER} /var/log/opentsdb && chown -R ${APP_USER}:${IUSER} /tmp/opentsdb && chown -R ${APP_USER}:${IUSER} /usr/share/opentsdb && su -c /etc/opentsdb/run.sh ${APP_USER}",
  "cpus": ${APP_CPU},
  "mem": ${APP_MEM},
  "instances": ${APP_CNT},
  "env": {
   "HADOOP_HOME": "/opt/mapr/hadoop/hadoop-2.7.0",
   "JAVA_HOME": "/usr/lib/jvm/java-8-openjdk-amd64"
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
      { "containerPath": "/etc/opentsdb", "hostPath": "${APP_CONF_DIR}", "mode": "RW" },
      { "containerPath": "/var/log/opentsdb", "hostPath": "${APP_LOG_DIR}", "mode": "RW" },
      { "containerPath": "/usr/share/opentsdb/plugins", "hostPath": "${APP_PLUGIN_DIR}", "mode": "RW" },
      { "containerPath": "/opt/mapr", "hostPath": "/opt/mapr", "mode":"RO"}
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


