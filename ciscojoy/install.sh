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
APP_STREAM="joystreams"
echo ""
read -e -p "How many partitions do you want by default for topics in your streamm: " -i "3" APP_DEF_PART
echo ""
read -e -p "What user should we create the stream data as? " -i "zetasvc${APP_ROLE}" APP_USER
echo ""
read -e -p "Pin to the following node (Use IP Address) (Blank for no constraints): " -i "" APP_NODE
echo ""
echo "Cisco Joy Interfaces are odd with docker, and will likely start intf When it start, if you get an error you may have to adjust in $APP_HOME/conf/options.cfg: "
read -e -p "What interface should we run this on: " -i "eno1" APP_INT
echo ""

APP_SUB=$(echo "$APP_MAR_ID"|sed "s@/@ @g")
APP_OUT=$(echo "$APP_SUB"| sed 's/ /\n/g' | tac | sed ':a; $!{N;ba};s/\n/ /g'|tr " " "-")

APP_MAR_FILE="${APP_HOME}/marathon.json"
APP_CONF_DIR="$APP_HOME/conf"
APP_BIN_DIR="$APP_HOME/bin"
APP_LOG_DIR="$APP_HOME/log"
APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"


if [ "$APP_NODE" != "" ]; then
    APP_CON="\"constraints\": [[\"hostname\",\"LIKE\",\"$APP_NODE\"]],"
else
    APP_CON=""
fi

mkdir -p $APP_CONF_DIR
mkdir -p $APP_BIN_DIR
mkdir -p $APP_LOG_DIR
sudo chmod 770 $APP_CONF_DIR
sudo chmod 770 $APP_BIN_DIR
sudo chmod 770 $APP_LOG_DIR


cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_PORT="${APP_PORT}"
EOL1



cat > $APP_CONF_DIR/options.cfg << EOO
# options.cfg
# 
# configuration file for advanced flow data capture

# File Format
#
# There should be a single command on each line.  Commands have the
# form "command" or "command = value", where value can be a boolean,
# an integer, or a string (with no quotes around strings).  If
# "command = 1" is valid, then "command" is a synonym for "command =
# 1".  Omitting "command" from the file is the same as "command = 0".
# Whitespace is unimportant.

# Network options
# 
# An interface must be specified for live data capture; linux uses
# eth0 and wlan0, MacOS uses en0.  Can be set to "auto", which is
# recommended, since it will then select an active, non-loopback
# interface automatically.  It can also be set to "none", in which
# case the interface must be specified on the command line, via the
# "-l" option.
interface = $APP_INT

# Promiscuous mode will monitor traffic sent to any destination, not
# just the observation point
promisc = 1

# Output options
#
# output = the file to which flow records are written
# output = /var/log/darkstar
output = /app/fifo/joy.fifo

# outdir sets the directory to which flow record output files are
# written
outdir = /app/fifo

# logfile sets the secondary output stsream, that is, the file to
# which error/warnings/info/debug statements will be sent; if this
# value is "none", then stderr will be used
logfile = /app/log/joy.log

# count = the number of flow records that will be obtained before the
# capture file is rotated; if this number is nonzero, then files will
# be rotated, and the n-th output file will have "-n" appended to it
#count = 0

# SSH/rsync user and server; if this is set, then capture files will
# be uploaded after rotation
# upload = data@fqdn:path
# SSH identity (private key) file used to authenticate to the "upload"
# server; the corresponding public key file must be present in the
# ~/.ssh/authorized_hosts file on that server
#
# example key generation: ssh-keygen -b 2048 -f upload-key -P ""
#keyfile = /usr/local/etc/joy/upload-key

# retain=1 causes a local copy of the capture file to be retained
# after it is uploaded
retain = 0

# Data options
# 
# bidir=1 causes flow stitching between directions to take place, so
# that flows will be reported as bidirectional (though flows with no
# matching reverse-direction twin will still be reported as
# unidirectional)
bidir = 1

# Sequence of Application Lengths and Times (SALT) and Sequence of
# Packet Lengths and Times (SPLT) options
# 
# num_pkts is the maximum number of entries in the SALT and SPLT
# arrays; it can be set to 0, or up to 200 (depending on compilation
# options)
# 
# if num_pkts=0, then no lengths and times will be reported
num_pkts = 200

# type=1 is SPLT, type = 2 is SALT
type = 1

# zeros=1 causes the zero-length messages to be included in length
# and time arrays
zeros = 0

# Byte Distribution options
#
# dist=1 causes the byte count distribution to be reported
dist = 1

# entropy=1 causes the entropy to be reported
entropy = 1

# Executable/process information
# 
# exe=1 causes the path name of the executable associated with a flow
# that originates/terminates on the host to be included in the flow
# record
# 
exe = 1


# Transport Layer Security (TLS) options
# 
# tls=1 causes TLS application data lengths and times and ciphersuites
# to be reported
tls = 1

# Initial Data Packet (IDP)
#
# idp=<num> causes <num> bytes of the initial data packet of each
# unidirectional flow to be reported; setting idp to zero causes no
# such data to be reported; idp=1460 is a good example
idp = 1500

# Passive Operating System inference inference
#
# set p0f=sock, where "sock" is a UNIX socket used to communicate
# between p0f and client processes; p0f should be run with the "-s
# sock" argument
# 
# p0f = sock

# Traffic Selection
#
# if bpf is set to a Berkeley Packet Filter (BPF) expression, then
# only traffic matching that expression will be reported on, e.g.
# "bpf = tcp port 443 or ip host 216.34.181.45".  Leave bpf unset to
# observe all IP traffic.
bpf = none


# Anonymization
# 
# when anon is set to the name of a file that contains a subnet (in
# address/number of bits in mask format) on each line, that file is
# read in; anon=internal.net anonymizes the RFC 1918 private addresses
anon = none
#anon = /usr/local/etc/joy/internal.net

# TLS Fingerprinting
#
# This is the path to the file that will be used by Joy
# as the known dataset upon which TLS flow fingerprinting
# will match entries. If you have placed a custom file in a different
# location, then specify the full path here.
aux_resource_path = /usr/local/etc/joy
# Verbosity
# 
# verbosity = 0 -> silent
# verbosity = 1 -> report a summary of each packet
# verbosity = 2 -> report on all data of each packet
verbosity = 1

EOO


@go.log INFO "Creating Volume and stream for logs"
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

@go.log WARN "Creating runall script"
cat > $APP_BIN_DIR/runall.sh << EOZ

#!/bin/bash

CAP_IF="$APP_INT"
LOG_PIPE_DIR="/app/fifo"
LOG_PIPE="joy.fifo"
FULL_LOG_PIPE="\${LOG_PIPE_DIR}/\$LOG_PIPE"
STREAM_USER="\$CAP_USER"

CLUSTERNAME="$CLUSTERNAME"
HDFSBASE="$HDFSBASE"
BASEDIR="$BASEDIR"
VOLNAME="streams"
STREAMNAME="$APP_STREAM"
TOPIC="joylogs"
ifconfig \$CAP_IF up


STREAMBASE="\${HDFSBASE}/\${VOLNAME}/\${STREAMNAME}"
FULL_TOPIC="\${STREAMBASE}:\$TOPIC"
if [ ! -d "\$LOG_PIPE_DIR" ]; then
    echo "\$LOG_PIPE_DIR Not Found - Creating!"
    mkdir -p \$LOG_PIPE_DIR
    rm -f \$FULL_LOG_PIPE
    mkfifo \$FULL_LOG_PIPE
    chown -R \$STREAM_USER:root \$LOG_PIPE_DIR
    chmod -R 770 \$LOG_PIPE_DIR
fi

# Start
echo "Running on Topic: \$TOPIC from \$FULL_LOG_PIPE"
echo ""
echo "Starting Kafka Cat"
cat \$FULL_LOG_PIPE | su -c "kafkacat -P -p -1 -b '' -t \$FULL_TOPIC " \$STREAM_USER &
echo ""
joy -x /app/conf/options.cfg

EOZ

chmod +x $APP_BIN_DIR/runall.sh

cat > $APP_MAR_FILE << EOL
{
  "id": "${APP_MAR_ID}",
  "cmd": "/app/bin/runall.sh",
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
      { "containerPath": "/app/conf", "hostPath": "${APP_CONF_DIR}", "mode": "RO" },
      { "containerPath": "/app/bin", "hostPath": "${APP_BIN_DIR}", "mode": "RO" },
      { "containerPath": "/app/log", "hostPath": "${APP_LOG_DIR}", "mode": "RW" },
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


