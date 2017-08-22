#!/bin/bash

###############
# $APP Specific
echo ""
echo ""

echo "The next step will walk through instance defaults for ${APP_ID}"
echo ""
read -e -p "Please enter the CPU shares to use with $APP_NAME: " -i "1.0" APP_CPU
echo ""
read -e -p "Please enter the Marathon Memory limit to use with $APP_NAME: " -i "1024" APP_MEM
echo ""
read -e -p "How many instances of $APP_NAME for $APP_ID do you wish to run: " -i "1" APP_CNT
echo ""
APP_STREAM="brostreams"
echo ""
read -e -p "How many partitions do you want by default for topics in your streamm: " -i "3" APP_DEF_PART
echo ""
read -e -p "What user should we create the stream data as? " -i "zetasvc${APP_ROLE}" APP_USER
echo ""
read -e -p "Pin to the following node (Use IP Address) (Blank for no constraints): " -i "" APP_NODE
echo ""
read -e -p "What interface should we run this on: " -i "eth0" APP_INT
echo ""
echo "We can enable multiple logs, however, you will need to test performance, on large installations one log per container probably makes sense"
echo "Logs that can be selected: (enter each log name, space sep)"
echo "conn dce_rpc dhcp dnp3 dns files ftp http irc kerbeos modbus ntlm pe radius rdp rfb smtp snmp socks ssh ssl syslog tunnel weird x509 software stats dpd"
read -e -p "Logs to enable sep by space: " -i "conn dns http" APP_LOGS
echo ""

APP_SUB=$(echo "$APP_MAR_ID"|sed "s@/@ @g")
APP_OUT=$(echo "$APP_SUB"| sed 's/ /\n/g' | tac | sed ':a; $!{N;ba};s/\n/ /g'|tr " " "-")

APP_MAR_FILE="${APP_HOME}/marathon.json"
APP_CONF_DIR="$APP_HOME/conf"
APP_BIN_DIR="$APP_HOME/bin"

APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"


if [ "$APP_NODE" != "" ]; then
    APP_CON="\"constraints\": [[\"hostname\",\"LIKE\",\"$APP_NODE\"]],"
else
    APP_CON=""
fi

mkdir -p $APP_CONF_DIR
mkdir -p $APP_BIN_DIR
sudo chmod 770 $APP_CONF_DIR
sudo chmod 770 $APP_BIN_DIR


cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_PORT="${APP_PORT}"
EOL1

@go.log INFO "Copying Default Configs from Container"
CID=$(sudo docker run -d $APP_IMG sleep 10)
sudo docker cp $CID:/opt/bro/etc $APP_CONF_DIR
sudo chown -R $IUSER:$IUSER $APP_CONF_DIR
mv $APP_CONF_DIR/etc/* $APP_CONF_DIR/
rm -rf $APP_CONF_DIR/etc
sudo docker kill $CID
sudo docker rm $CID
echo ""

@go.log INFO "Setting no rotation on logs (we used named pipes)"
sed -i "s/LogRotationInterval = 3600/LogRotationInterval = 0/g" $APP_CONF_DIR/broctl.cfg
@go.log INFO "Setting Interface"
sed -i "s/interface=eth0/interface=${APP_INT}/g" $APP_CONF_DIR/node.cfg


MYGO="$_GO_SCRIPT"

MAPRCLI="$MYGO fs mapr maprcli -U=mapr"
BASEDIR="$APP_HOME"
HDFSBASE=$(echo "$APP_HOME"|sed "s@${CLUSTERMOUNT}@@g")

if [ ! -d "$BASEDIR/streams" ]; then
    $MAPRCLI volume create -path $HDFSBASE/streams -rootdirperms 775 -user "zetaadm:fc,a,dump,restore,m,d mapr:fc,a,dump,restore,m,d" -ae zetaadm -name "${APP_ROLE}.${APP_DIR}.${APP_ID}.streams"
else
    echo "Volume Already Exists"
fi
@go.log WARN "Creating Stream!"
$MAPRCLI stream create -path $HDFSBASE/streams/$APP_STREAM -defaultpartitions $APP_DEF_PART -autocreate true -produceperm "\(u:mapr\|g:zeta${APP_ROLE}data\|u:zetaadm\)" -consumeperm "\(u:mapr\|g:zeta${APP_ROLE}data\|u:zetaadm\)" -topicperm "\(u:mapr\|g:zeta${APP_ROLE}data\|u:zetaadm\)" -adminperm "\(u:mapr\|g:zeta${APP_ROLE}data\|u:zetaadm\)"
echo ""


@go.log INFO "Creating start script in $APP_BIN_DIR"
cat > $APP_BIN_DIR/runall.sh << EOR
#!/bin/bash
# Conf Items

CAP_IF="\$CAP_IFACE"
STREAM_USER="\$CAP_USER"
STREAMBASE="\$CAP_DEST"
ENABLED_LOGS="\$CAP_LOGS"


SRC_BASE="/opt/bro/spool/bro"
ifconfig \$CAP_IF up
BRO_LOCAL="/opt/bro/share/bro/site/local.bro"
JSON_LOG="/opt/bro/share/bro/site/scripts/json-logs.bro"
LOG_SETTINGS="/opt/bro/share/bro/site/scripts/stream-logs.bro"

if [ ! -d "\$SRC_BASE" ]; then
    echo "\$SRC_BASE Not Found - Creating!"
    mkdir -p \$SRC_BASE
fi



# List of all the logs available

BROKEN="known_certs~Known::CertsInfo known_devices~Known::DevicesInfo known_hosts~Known::HostsInfo known_services~Known::ServicesInfo modbus_register_change~Modubus::MemmapInfo smb_cmd~SMB::CmdInfo smb_files~SMB::FileInfo smb_mapping~SMB::TreeInfo mysql~MySQL"

ALL_LOGS="conn~Conn::LOG dce_rpc~DCE_RPC::LOG dhcp~DHCP::LOG dnp3~DNP3::LOG dns~DNS::LOG files~Files::LOG ftp~FTP::LOG http~HTTP::LOG irc~IRC::LOG kerbeos~KRB::LOG modbus~Modbus::LOG"
ALL_LOGS="\${ALL_LOGS} ntlm~NTLM::LOG pe~PE::LOG radius~RADIUS::LOG rdp~RDP::LOG rfb~RFB::LOG smtp~SMTP::LOG snmp~SNMP::LOG socks~SOCKS::LOG ssh~SSH::LOG ssl~SSL::LOG syslog~Syslog::LOG"
ALL_LOGS="\${ALL_LOGS} tunnel~Tunnel::LOG weird~Weird::LOG x509~X509::LOG software~Software::LOG stats~Stats::LOG dpd~DPD::LOG"




echo "Checking on JSON Loggings"
if [ ! -f \$JSON_LOG ]; then
    echo "JSON logging script not found - Creating!"
    mkdir -p /opt/bro/share/bro/site/scripts
tee \$JSON_LOG << EOF
@load tuning/json-logs

redef LogAscii::json_timestamps = JSON::TS_ISO8601;
redef LogAscii::use_json = T;
EOF
else
    echo "JSON Logging script found - not creating!"
fi

# Removing any previous log settings file
rm \$LOG_SETTINGS
touch \$LOG_SETTINGS

##################################################
echo "Checking for json updates in local.bro"
CHK=\$(cat \$BRO_LOCAL|grep "json-logs")
if [ "\$CHK" == "" ]; then
    echo "Updating local file for json logging"
tee -a \$BRO_LOCAL << EOL

# Load policy for JSON output
@load scripts/json-logs
EOL
else
    echo "Local file already updated for Json!"
fi

echo "Checking for log disabled in local.bro"
NCHK=\$(cat \$BRO_LOCAL|grep "stream-logs")
if [ "\$NCHK" == "" ]; then
    echo "Updating local file for json logging"
tee -a \$BRO_LOCAL << EOL
# Load policy for JSON output
@load scripts/stream-logs
EOL
else
    echo "Local file already updated for Streams!"
fi
echo "event bro_init()" >> \$LOG_SETTINGS
echo "{" >> \$LOG_SETTINGS

##################################################
#First create the log settings file (disabling logs that are disabled)
for LOG in \$ALL_LOGS; do
    LBASE=\$(echo "\$LOG"|cut -d"~" -f1)
    LINT=\$(echo "\$LOG"|cut -d"~" -f2)
    LFILE="\${LBASE}.log"
    CHK=\$(echo "\$ENABLED_LOGS"|grep "\$LBASE")
    if [ "\$CHK" == "" ]; then
        # This log is not enabled, so disable it
        echo "Log::disable_stream(\$LINT);" >> \$LOG_SETTINGS
    fi
done
echo "}" >> \$LOG_SETTINGS

#Then set up Kafka Cat 
for LOG in \$ENABLED_LOGS; do
    echo "Working with \$LOG"
    LBASE=\$LOG
    LFILE="\${LBASE}.log"

    echo "Setting up log \$LBASE"
    CUR_PIPE="\$SRC_BASE/\${LFILE}"
    # Create the Named Pipe for fun and profit
    rm -f \$CUR_PIPE && mkfifo \$CUR_PIPE && chmod 775 \$CUR_PIPE
    TOPIC="\${STREAMBASE}:\${LBASE}"
    # Start Kafkacat (Perhaps we should try with just a few at first?)
    # Perhaps this should be adding to supervisord at the the end of the day!

tee -a /etc/supervisor/conf.d/supervisord.conf << EOA

[program:kafkacat_\$LBASE]
command=bash -c "cat \$CUR_PIPE | su -c \"/usr/local/bin/kafkacat -P -p -1 -b '' -t \$TOPIC\" \$STREAM_USER"
EOA

done

echo "Starting SupervisorD!"
/usr/bin/supervisord -c /etc/supervisor/supervisord.conf


EOR
chmod +x $APP_BIN_DIR/runall.sh

cat > $APP_MAR_FILE << EOL
{
  "id": "${APP_MAR_ID}",
  "cmd": "/opt/bro/streamsbin/runall.sh",
  "cpus": ${APP_CPU},
  "mem": ${APP_MEM},
  "instances": 1,
  $APP_CON
  "env": {
    "CAP_USER": "$APP_USER",
    "CAP_IFACE": "$APP_INT",
    "CAP_DEST": "${HDFSBASE}/streams/${APP_STREAM}",
    "CAP_LOGS": "$APP_LOGS"
  },
  "labels": {
   "CONTAINERIZER":"Docker"
  },
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "${APP_IMG}",
      "network": "HOST",
      "privileged": true
    },
    "volumes": [
      { "containerPath": "/opt/bro/etc", "hostPath": "${APP_CONF_DIR}", "mode": "RW" },
      { "containerPath": "/opt/bro/streamsbin", "hostPath": "${APP_BIN_DIR}", "mode": "RW" },
      { "containerPath": "/opt/mapr", "hostPath": "/opt/mapr", "mode": "RO" }
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


