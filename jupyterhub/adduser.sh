#!/bin/bash

APP_ROLE="prod"
IUSER="zetaadm"
APP_ID="jupprod"
USER_BASE="/zeta/brewpot/user"
USER_LIST="/zeta/brewpot/zeta/prod/jupyterhub/jupprod/conf/users.json"
APP_VER="0.7.2"
ZETAGO="/home/zetaadm/homecluster/zetago"
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

read -e -p "Please enter the amount of RAM to allow for $APP_USER: " -i "2G" APP_MEM
echo ""
read -e -p "Please enter the amount of CPU to use for $APP_USER: " -i "1" APP_CPU
echo ""
read -e -p "Please enter the default app image: " -i "dockerregv2-shared.marathon.slave.mesos:5005/jupyternotebook:$APP_VER" APP_IMG
echo ""
echo "Attempting to pull $APP_IMG - If it's not built yet and pushed to docker reg, than do that."
sudo docker pull $APP_IMG
if [ "$?" != "0" ]; then
    echo "We must be able to pull $APP_IMG to install default conf in user directory - Exiting"
    exit 1
fi
JUP_HOME="${USER_BASE}/${APP_USER}/.jupyter"
sudo mkdir -p $JUP_HOME
sudo chown -R $APP_USER:$IUSER $JUP_HOME
sudo chmod 750 $JUP_HOME

if [ -f "$JUP_HOME/jupyter_notebook_config.py" ]; then
    echo "An existing jupyter_notebook_config.py was found at $JUP_HOME - Not going to recreate"
else
    sudo docker run -it --rm -v=$JUP_HOME:/root/.jupyter $APP_IMG jupyter notebook --generate-config --allow-root
    sudo cp ${JUP_HOME}/jupyter_notebook_config.py ${JUP_HOME}/jupyter_notebook_config.py.template
    sudo chown $APP_USER:$IUSER ${JUP_HOME}/jupyter_notebook_config.py
    sudo chown $APP_USER:$IUSER ${JUP_HOME}/jupyter_notebook_config.py.template
fi

echo ""
read -e -p "Please enter the network mode to use (HOST if using Spark etc, else bridge should be ok): " -i "BRIDGE" APP_NET_MODE
echo ""
echo ""

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


echo "{\"user\": \"${APP_USER}\", \"cpu_limit\": ${APP_CPU}, \"mem_limit\": \"${APP_MEM}\", \"user_ssh_port\": ${APP_SSH_PORT}, \"user_web_port\": ${APP_WEB_PORT}, \"network_mode\": \"${APP_NET_MODE}\", \"app_image\": \"${APP_IMG}\", \"marathon_constraints\": []}" >> $USER_LIST

#  # { "user": "username", "cpu_limit": "1", "mem_limit": "2G", "user_ssh_port": 10500, "user_web_port:" 10400, "network_mode": "BRIDGE", "app_image": "$APP_IMG", "marathon_constraints": []}


