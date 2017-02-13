#!/bin/bash

###############
# $APP Specific
echo "The next step will walk through instance defaults for ${APP_ID}"
echo ""
read -e -p "Please enter the CPU shares to use with $APP_NAME: " -i "4.0" APP_CPU
echo ""
echo "For Minecraft memory, we will take the Marathon Memory limit and subtract 128mb from it for head room"
echo ""
read -e -p "Please enter the Marathon Memory limit to use with $APP_NAME: " -i "5120" APP_MEM
APP_MC_MEM=$((APP_MEM-256))
echo ""
echo "The Minecraft memory limit will be $APP_MC_MEM"
echo ""


SOME_COMMENTS="Port for Minecraft Server"
PORTSTR="CLUSTER:tcp:25565:${APP_ROLE}:${APP_ID}:$SOME_COMMENTS"
getport "CHKADD" "$SOME_COMMENTS" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME instance $APP_ID with $PSTR"
fi


bridgeports "APP_PORT_JSON" "25565" "$APP_PORTSTR"
haproxylabel "APP_HA_PROXY" "${APP_PORTSTR}"


APP_MAR_FILE="${APP_HOME}/marathon.json"
APP_DATA_DIR="$APP_HOME/appdata"
APP_ENV_FILE="$CLUSTERROOT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"


mkdir -p $APP_DATA_DIR
mkdir -p ${APP_DATA_DIR}/lock
sudo chmod 770 $APP_DATA_DIR


cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_PORT="${APP_PORT}"
EOL1


cat  > ${APP_DATA_DIR}/start.sh << EOL2
#!/bin/bash

STARTMEM="${APP_MC_MEM}M"
MAXMEM="${APP_MC_MEM}M"

JARLOC="/minecraft/"
JAR="$APP_JAR"

OTHEROPTS="-XX:+UseConcMarkSweepGC -XX:+UseParNewGC -XX:+CMSIncrementalPacing -XX:ParallelGCThreads=2 -XX:+AggressiveOpts"

java -server -Xms\$STARTMEM -Xmx\$MAXMEM \$OTHEROPTS -jar \${JARLOC}\${JAR} nogui
EOL2

chmod +x ${APP_DATA_DIR}/start.sh

@go.log INFO "Copying Jar File to App Data Dir"
cp ${APP_PKG_DIR}/$APP_JAR $APP_DATA_DIR


read -e -p "Do you wish to auto accept the EULA for Minecraft?" -i "Y" ACCEPT_EULA
if [ "$ACCEPT_EULA" == "Y" ]; then
cat > ${APP_DATA_DIR}/eula.txt << EOL5
#By changing the setting below to TRUE you are indicating your agreement to our EULA (https://account.mojang.com/documents/minecraft_eula).
#Fri Jan 20 20:53:36 UTC 2017
eula=true

EOL5
else
    @go.log WARN "If you don't adjust the eula.txt manually to eula=true, your minecraft server won't start ($APP_DATA_DIR/eula.txt)"
fi


cat > ${APP_DATA_DIR}/lockfile.sh << EOL3
#!/bin/bash

#The location the lock will be attempted in
LOCKROOT="/minecraft/lock"
LOCKDIRNAME="lock"
LOCKFILENAME="mylock.lck"

#This is the command to run if we get the lock.
RUNCMD="/minecraft/start.sh"

#Number of seconds to consider the Lock stale, this could be application dependent.
LOCKTIMEOUT=60
SLEEPLOOP=30

LOCKDIR=\${LOCKROOT}/\${LOCKDIRNAME}
LOCKFILE=\${LOCKDIR}/\${LOCKFILENAME}


if mkdir "\${LOCKDIR}" &>/dev/null; then
    echo "No Lockdir. Our lock"
    # This means we created the dir!
    # The lock is ours
    # Run a sleep loop that puts the file in the directory
    while true; do date +%s > \$LOCKFILE ; sleep \$SLEEPLOOP; done &
    #Now run the real shell scrip
    \$RUNCMD
else
    #Pause to allow another lock to start
    sleep 1
    if [ -e "\$LOCKFILE" ]; then
        echo "lock dir and lock file Checking Stats"
        CURTIME=\`date +%s\`
        FILETIME=\`cat \$LOCKFILE\`
        DIFFTIME=\$((\$CURTIME-\$FILETIME))
        echo "Filetime \$FILETIME"
        echo "Curtime \$CURTIME"
        echo "Difftime \$DIFFTIME"

        if [ "\$DIFFTIME" -gt "\$LOCKTIMEOUT" ]; then
            echo "Time is greater then Timeout We are taking Lock"
            # We should take the lock! First we remove the current directory because we want to be atomic
            rm -rf \$LOCKDIR
            if mkdir "\${LOCKDIR}" &>/dev/null; then
                while true; do date +%s > \$LOCKFILE ; sleep \$SLEEPLOOP; done &
                \$RUNCMD
            else
                echo "Cannot Establish Lock file"
                exit 1
            fi
        else
            # The lock is not ours.
            echo "Cannot Estblish Lock file - Active "
            exit 1
        fi
    else
        # We get to be the locker. However, we need to delete the directory and recreate so we can be all atomic about
        rm -rf \$LOCKDIR
        if mkdir "\${LOCKDIR}" &>/dev/null; then
            while true; do date +%s > \$LOCKFILE ; sleep \$SLEEPLOOP; done &
            \$RUNCMD
        else
            echo "Cannot Establish Lock file - Issue"
            exit 1
        fi
    fi
fi
EOL3

chmod +x ${APP_DATA_DIR}/lockfile.sh


cat > $APP_MAR_FILE << EOL
{
  "id": "${APP_MAR_ID}",
  "cmd": "cd /minecraft && ./lockfile.sh",
  "cpus": ${APP_CPU},
  "mem": ${APP_MEM},
  "instances": 1,
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
      { "containerPath": "/minecraft", "hostPath": "${APP_DATA_DIR}", "mode": "RW" }
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


