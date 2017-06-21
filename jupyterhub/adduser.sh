#########################################################
#

echo ""
read -e -p "Please enter the username to enable in $APP_ID instance of $APP_NAME: " -i "zetasvc${APP_ROLE}" APP_USER
echo ""
CHKID=$(id $APP_USER)
if [ "$CHKID" == "" ]; then
    echo "User $APP_USER not found by id command: will cowardly refuse to install"
    exit 1
fi

CHKUSER=$(grep "$APP_USER" $USER_LIST)
if [ "$CHKUSER" != "" ]; then
    echo "User $APP_USER already in $USER_LIST - Exiting"
    exit 1
fi

echo ""
echo "Getting Information for user $APP_USER"
echo ""
read -e -p "Please enter the amount of RAM to allow for $APP_USER: " -i "2G" APP_MEM
echo ""
read -e -p "Please enter the amount of CPU to use for $APP_USER: " -i "1" APP_CPU
echo ""
read -e -p "Please enter the default app image (name only): " -i "jupyternotebook" APP_IMG_NAME
echo ""
read -e -p "Please enter the tag to use: " -i "$APP_VER" APP_IMG_TAG
echo ""
read -e -p "Please enter the network mode to use (HOST if using Spark etc, else bridge should be ok): " -i "HOST" APP_NET_MODE
echo ""
read -e -p "Please specific an org name for use in user help screens: " -i "$CLUSTERNAME - $APP_ID" APP_ORG_NAME
echo ""
ALL=$(curl -s --cacert /etc/ssl/certs/ca-certificates.crt https://${REG_URL}/v2/_catalog)
CHK=$(echo "$ALL"|grep "$APP_IMG_NAME")
if [ "$CHK" != "" ]; then
    REPOS=$(curl -s --cacert /etc/ssl/certs/ca-certificates.crt   https://${REG_URL}/v2/${APP_IMG_NAME}/tags/list)
    CHKR=$(echo "$REPOS"|grep "$APP_IMG_TAG")
    if [ "$CHKR" != "" ]; then
        echo "Image: $APP_IMG_NAME:$APP_IMG_TAG Found on $REG_URL"
        APP_IMG="$REG_URL/$APP_IMG_NAME:$APP_IMG_TAG"
    else
        echo "Found $APP_IMG_NAME on $REG_URL, but no tag $APP_IMG_TAG - Exiting"
        exit 1
    fi
else
    echo "Did not find Image $APP_IMG_NAME on $REG_URL - Exiting"
    exit 1
fi
USER_HOME="${USER_BASE}/${APP_USER}"
USER_BIN="$USER_HOME/bin"
JUP_DIR="${USER_HOME}/.jupyter"
NB_DIR="${USER_HOME}/notebooks"

NB_SHARED_DIR=$(cat $JUP_CONF|grep shared_notebook_dir|cut -d"=" -f2|sed "s/[\" ]//g")

sudo mkdir -p $JUP_DIR
sudo chown -R $APP_USER:$IUSER $JUP_DIR
sudo chmod 750 $JUP_DIR

sudo mkdir -p $NB_DIR
sudo chown -R $APP_USER:$IUSER $NB_DIR
sudo chmod 750 $NB_DIR

sudo mkdir -p $USER_BIN
sudo chown -R $APP_USER:$IUSER $USER_BIN
sudo chmod 750 $USER_BIN

if [ "$USE_EDWIN" == "Y" ]; the
    IP_DIR="${USER_HOME}/.ipython
    START_IP_DIR="${IP_DIR}/profile_default/startup"
    sudo mkdir -p $START_IP_DIR
    sudo chown -R $APP_USER:$IUSER $IP_DIR
    sudo chmod 750 $IP_DIR
cat > $START_IP_DIR/00-edwin.py << EOJ
from edwin_core import Edwin
ip = get_ipython()
ed = Edwin(ip)
ip.register_magics(ed)
EOJ
    chown $APP_USER:$IUSER $START_IP_DIR/00-edwin.py
    chmod 770 $START_IP_DIR/00-edwin.py
fi


if [ "$NB_SHARED_DIR" != "" ]; then
    echo "Shared Dir found at: $SHARED_DIR - Linking to $NB_DIR"
    sudo ln -s $NB_SHARED_DIR ${NB_DIR}/shared_notebooks
else
    echo "Shared Dir not identified in $JUP_CONF"
fi

if [ -f "$JUP_HOME/jupyter_notebook_config.py" ]; then
    echo "An existing jupyter_notebook_config.py was found at $JUP_HOME - Not going to recreate"
else
    sudo docker run -it --rm -v=$JUP_DIR:/root/.jupyter $APP_IMG jupyter notebook --generate-config --allow-root
    sudo cp ${JUP_DIR}/jupyter_notebook_config.py ${JUP_DIR}/jupyter_notebook_config.py.template
    sudo chown $APP_USER:$IUSER ${JUP_DIR}/jupyter_notebook_config.py
    sudo chown $APP_USER:$IUSER ${JUP_DIR}/jupyter_notebook_config.py.template
fi


echo "Getting Web Port"
APP_WEB_PORTSTR=$($ZETAGO/zeta network requestport -p=10400 -t="tcp" -r="${APP_ROLE}" -i="${APP_ID}" -c="Web port for $APP_USER Notebook"|grep PORTRESULT|cut -d"#" -f2)

if [ "$APP_WEB_PORTSTR" != "" ]; then
    APP_WEB_PORT=$(echo "$APP_WEB_PORTSTR"|cut -d":" -f3)
else
    echo "Failed to get port for web, exiting now"
    exit 1
fi
echo ""
echo "Getting SSH Port"
APP_SSH_PORTSTR=$($ZETAGO/zeta network requestport -p=10500 -t="tcp" -r="${APP_ROLE}" -i="${APP_ID}" -c="SSH port for $APP_USER Notebook"|grep PORTRESULT|cut -d"#" -f2)
if [ "$APP_SSH_PORTSTR" != "" ]; then
    APP_SSH_PORT=$(echo "$APP_SSH_PORTSTR"|cut -d":" -f3)
else
    echo "Failed to get port for ssh, exiting now"
    exit 1
fi
APP_SSH_HOST="${APP_USER}-${NOTE_URL_BASE}"
CHKEDG=$(echo "$APP_SSH_PORTSTR"|grep -i "EDGE")
if [ "$CHKEDG" == "" ]; then
    echo "SSH is a cluster port, going to use the marathon url to get to the hostname: $APP_SSH_HOST"
else
    echo ""
    echo "EDGE networking for SSH port selected, this means sometimes you wish to use an edge or proxy node for users to connect"
    echo "Please enter that name now:"
    read -e -p "Enter Edge Node for users to connect via SSH with: " -i "$APP_SSH_HOST" APP_SSH_HOST
fi

DEF_FILES="profile nanorc bashrc"
echo ""
echo "Copying default $DEF_FILES to $USER_HOME"
echo ""
for DFILE in $DEF_FILES; do
    SRCFILE="${DFILE}_template"
    DSTFILE=".${DFILE}"
    if [ -f "${USER_HOME}/${DSTFILE}" ]; then
        read -e -p "${USER_HOME}/${DSTFILE} exists, should we replace it with the default $DSTFILE? " -i "N" CPFILE
    else
        CPFILE="Y"
    fi

    if [ "$CPFILE" == "Y" ]; then
       sudo cp ${APP_TEMPLATES}/$SRCFILE ${USER_HOME}/$DSTFILE
       sudo chown $APP_USER:$IUSER ${USER_HOME}/$DSTFILE
    fi
done
INSTRUCTIONS=$(grep "Zeta Cluster User Shell" ${USER_HOME}/.profile)

if [ "$INSTRUCTIONS" == "" ]; then


sudo tee -a ${USER_HOME}/.profile << EOF
CLUSTERNAME="$CLUSTERNAME"
CLUSTERMOUNT="$CLUSTERMOUNT"
echo ""
echo "**************************************************************************"
echo "Zeta Cluster User Shell"
echo ""
echo "This simple shell is a transient container that allows you to do some basic exploration of the Zeta Environment"
echo ""
echo "Components to be aware of:"
echo "- If a Drill Instance was installed with this shell, you can run a Drill Command Line Shell (SQLLine) by simply typing 'zetadrill' and following the authentication prompts"
echo "- If a Spark instance was installed with this shell, you can run a Spark pyspark interactive shell by by simply typing 'zetaspark'"
echo "- Java is in the path and available for use"
echo "- Python is installed and in the path"
echo "- The hadoop client (i.e. hadoop fs -ls /) is in the path and available"
echo "- While the container is not persistent, the user's home directory IS persistent. Everything in /home/$APP_USER will be maintained after the container expires"
echo "- $CLUSTERMOUNT is also persistent.  This is root of the distributed file system. (I.e. ls $CLUSTERMOUNT has the same result as hadoop fs -ls /)"
echo "- The user's home directory is also in the distributed filesystem. Thus, if you save a file to /home/\$APP_USER it also is saved at $CLUSTERMOUNT/user/\$USER. This is usefule for running distributed drill queries."
echo ""
echo "This is a basic shell environment. It does NOT have the ability to run docker commands, and we would be very interested in other feature requests."
echo ""
echo "**************************************************************************"
echo ""
EOF
fi

MYENVS="{\"ORG_NAME\":\"$APP_ORG_NAME\"}"

if [ "$FS_HADOOP_HOME" != "" ];then
    if [ ! -f "${USER_BIN}/hadoop" ]; then
        HADOOP_HOME="$FS_HADOOP_HOME"
        echo  "Linking Hadoop Client for use in Container"
        ln -s $HADOOP_HOME/bin/hadoop ${USER_BIN}/hadoop
    fi
fi
if [ "$DRILL_HOME" != "" ]; then
    if [ ! -f "$USER_BIN/zetadrill" ]; then
        echo "Linking zetadrill for use in container"
        ln -s $DRILL_HOME/zetadrill $USER_BIN/zetadrill
    fi
    if [ "$DRILL_BASE_URL" != "" ]; then
        MYENVS="$MYENVS,{\"DRILL_BASE_URL\":\"$DRILL_BASE_URL\"}"
    fi
fi

if [ "$SPARK_HOME" != "" ]; then
    if [ ! -f "$USER_BIN/zetaspark" ];then
        echo "Creating zetaspark shortcut"
cat > ${USER_BIN}/zetaspark << EOS
#!/bin/bash
SPARK_HOME="/spark"
cd \$SPARK_HOME
bin/pyspark
EOS
chmod +x ${USER_PATH}/zetaspark
    fi
    MYVOLS="[{\"containerPath\": \"/spark\", \"hostPath\": \"$SPARK_HOME\",\"mode\": \"RW\"}]"
    MYENVS="$MYENVS,{\"SPARK_HOME\":\"/spark\"}"

else
    MYVOLS="[]"
fi

if [ "$EDWIN_ORG_CODE" != "" ]; then
    MYENVS="$MYENVS,{\"EDWIN_ORG_CODE\":\"$EDWIN_ORG_CODE\"}"
fi

echo "{\"user\": \"${APP_USER}\", \"cpu_limit\": ${APP_CPU}, \"mem_limit\": \"${APP_MEM}\", \"user_ssh_host\": \"${APP_SSH_HOST}\", \"user_ssh_port\": ${APP_SSH_PORT}, \"user_web_port\": ${APP_WEB_PORT}, \"network_mode\": \"${APP_NET_MODE}\", \"app_image\": \"${APP_IMG}\", \"marathon_constraints\": [], \"volumes\": ${MYVOLS}, \"custom_env\": $MYENVS}" >> $USER_LIST

#  # { "user": "username", "cpu_limit": "1", "mem_limit": "2G", "user_ssh_port": 10500, "user_web_port:" 10400, "network_mode": "BRIDGE", "app_image": "$APP_IMG", "marathon_constraints": []}


