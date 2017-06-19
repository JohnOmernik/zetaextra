#!/bin/bash

###############
# $APP Specific
echo "The next step will walk through instance defaults for ${APP_ID}"
echo ""
read -e -p "Please enter the CPU shares to use with $APP_NAME: " -i "1.0" APP_CPU
echo ""
read -e -p "Please enter the Marathon Memory limit to use with $APP_NAME: " -i "512" APP_MEM
echo ""
read -e -p "Is there a shared notebook location this instance will use? Leave blank for none: " -i "$CLUSTERMOUNT/data/$APP_ROLE/$APP_ID/shared_notebooks" APP_SHARED_NOTEBOOK_DIR
echo ""
read -e -p "Please provide the admin user for this instance of $APP_NAME: " -i "zetasvc${APP_ROLE}" APP_ADMIN_USER
echo ""
@go.log WARN "Obtaining ports for Jupyter Hub itself"

PORTSTR="CLUSTER:tcp:22080:${APP_ROLE}:${APP_ID}:Hub Port for $APP_NAME"
getport "CHKADD" "Jupyter Hub Hub Port" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_HUB_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_HUB_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME instance $APP_ID with $PSTR"
fi

bridgeports "APP_HUB_PORT_JSON" "$APP_HUB_PORT" "$APP_HUB_PORTSTR"


PORTSTR="CLUSTER:tcp:22443:${APP_ROLE}:${APP_ID}:Web port for $APP_NAME"
getport "CHKADD" "Jupyter Hub Web Port" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_WEB_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_WEB_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME instance $APP_ID with $PSTR"
fi
bridgeports "APP_WEB_PORT_JSON" "${APP_WEB_PORT}" "$APP_WEB_PORTSTR"

haproxylabel "APP_HA_PROXY" "${APP_HUB_PORTSTR}~${APP_WEB_PORTSTR}"
portslist "APP_PORT_LIST" "${APP_HUB_PORTSTR}~${APP_WEB_PORTSTR}"
echo ""
APP_MAR_FILE="${APP_HOME}/marathon.json"
APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"

@go.log WARN "App Marathon ID of $APP_MAR_ID will be the base folder. Jupyter Hub will actually be ${APP_MAR_ID}/jupyterhub"

APP_MAR_ID_BASE=$APP_MAR_ID
APP_MAR_ID="$APP_MAR_ID/jupyterhub"

APP_SUB=$(echo "$APP_MAR_ID"|sed "s@/@ @g")
APP_OUT=$(echo "$APP_SUB"| sed 's/ /\n/g' | tac | sed ':a; $!{N;ba};s/\n/ /g'|tr " " "-")



CN_GUESS="${APP_OUT}.marathon.slave.mesos"
APP_API_URL="https://${CN_GUESS}:$APP_WEB_PORT"


APP_CONF_DIR="$APP_HOME/conf"
APP_DATA_DIR="$APP_HOME/data"
APP_LOG_DIR="$APP_HOME/log"
APP_CERT_LOC="$APP_HOME/certs"
APP_BUILD_DIR="$APP_HOME/Dockerbuild"
APP_TEMPLATE_DIR="$APP_HOME/templates"

@go.log WARN "Creating Application Directories and Securing them"
mkdir -p $APP_CONF_DIR
mkdir -p $APP_LOG_DIR
mkdir -p $APP_DATA_DIR
mkdir -p $APP_CERT_LOC
mkdir -p $APP_BUILD_DIR
mkdir -p $APP_TEMPLATE_DIR
mkdir -p $APP_SHARED_NOTEBOOK_DIR
sudo chown -R $IUSER:zeta${APP_ROLE}data $APP_CONF_DIR
sudo chown -R $IUSER:$IUSER $APP_LOG_DIR
sudo chown -R $IUSER:$IUSER $APP_BUILD_DIR
sudo chown -R $IUSER:$IUSER $APP_DATA_DIR
sudo chown -R $IUSER:$IUSER $APP_TEMPLATE_DIR
sudo chown -R $IUSER:zeta${APP_ROLE}data $APP_SHARED_NOTEBOOK_DIR
sudo chown -R $IUSER:$IUSER $APP_CERT_LOC
sudo chmod 770 $APP_CONF_DIR
sudo chmod 770 $APP_DATA_DIR
sudo chmod 770 $APP_BUILD_DIR
sudo chmod 770 $APP_SHARED_NOTEBOOK_DIR
sudo chmod 770 $APP_LOG_DIR
sudo chmod 770 $APP_TEMPLATE_DIR
sudo chmod 770 $APP_CERT_LOC
echo ""
@go.log WARN "Copying templates for user shells to $APP_TEMPLATE_DIR"
cp ${APP_PKG_BASE}/lib/profile_template ${APP_TEMPLATE_DIR}/
cp ${APP_PKG_BASE}/lib/nanorc_template ${APP_TEMPLATE_DIR}/
cp ${APP_PKG_BASE}/lib/bashrc_template ${APP_TEMPLATE_DIR}/
echo ""

@go.log WARN "Generating Certificate"
. $CLUSTERMOUNT/zeta/shared/zetaca/gen_server_cert.sh


@go.log WARN "Running $APP_IMG to generage config file template for reference"
sudo docker run -it --rm -v=$APP_CONF_DIR:/app $APP_IMG jupyterhub --generate-config
sudo chown zetaadm:zetaadm $APP_CONF_DIR/jupyterhub_config.py
mv $APP_CONF_DIR/jupyterhub_config.py $APP_CONF_DIR/jupyterhub_config.py.template


@go.log WARN "Creating adduser shell script in $APP_HOME"

@go.log WARN "The following three questions ask for home locations to provide access in the notebook containers. Clear (provide no answer) if you want to not link these apps"
@go.log WARN "Please ensure these home directories are accurate, or users will not get a good expierience"
echo ""
read -e -p "Please provide a Hadoop Home location (clear if you don't want to link in container). Usually the default works: " -i "/opt/mapr/hadoop/hadoop-2.7.0" APP_HADOOP
echo ""
read -e -p "Please provide a Drill Home location. This is the full path to the drill directory under your app instance (with version number in directory name): " -i "$CLUSTERMOUNT/zeta/prod/drill/drillprod/drill-0.10.0" APP_DRILL
echo ""
read -e -p "Please provide a Spark Home location. This is the full path to the spark directory under your app instace (Likely with version bin with hadoop in the directory name): " -i "$CLUSTERMOUNT/zeta/prod/spark/sparkprod/spark-2.1.1-bin-without-hadoop" APP_SPARK
echo ""
cat > $APP_HOME/adduser.sh << EOA
#!/bin/bash
CLUSTERNAME="$CLUSTERNAME"
CLUSTERMOUNT="$CLUSTERMOUNT"
APP_ROLE="$APP_ROLE"
IUSER="$IUSER"
APP_ID="$APP_ID"
USER_BASE="$CLUSTERMOUNT/user"
APP_HOME="$APP_HOME"
APP_CONF="${APP_HOME}/conf"
APP_TEMPLATES="${APP_HOME}/templates"
USER_LIST="\${APP_CONF}/users.json"
JUP_CONF="\${APP_CONF}/jupyterhub_config.py"
APP_VER="$APP_VER"
ZETAGO="`pwd`"
REG_URL="$ZETA_DOCKER_REG_URL"
FS_HADOOP_HOME="$APP_HADOOP"
DRILL_HOME="$APP_DRILL"
SPARK_HOME="$APP_SPARK"

EOA

cat ${APP_PKG_BASE}/adduser.sh >> $APP_HOME/adduser.sh
chmod +x $APP_HOME/adduser.sh

@go.log WARN "Creating ENV File at $APP_ENV_FILE"
cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_HOST="${CN_GUESS}"
export ZETA_${APP_NAME}_${APP_ID}_PORT="${APP_WEB_PORT}"
EOL1

APP_NOTEBOOK_IMG="$ZETA_DOCKER_REG_URL/jupyternotebook:$APP_VER"
@go.log WARN "Using $APP_NOTEBOOK_IMG as notebook image - Can be changed by building a new image at $APP_BUILD_DIR and updating the configuration"
cat > $APP_BUILD_DIR/build.sh << EOB
#!/bin/bash

IMG="$APP_NOTEBOOK_IMG"

sudo docker build --rm -t \$IMG .
sudo docker push \$IMG
EOB
chmod +x $APP_BUILD_DIR/build.sh

cat > $APP_BUILD_DIR/Dockerfile << EOD
FROM $ZETA_DOCKER_REG_URL/anaconda3:4.3.1

WORKDIR /app

RUN apt-get update && apt-get upgrade -y && apt-get install -y gcc libnss3 git curl && apt-get clean && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

RUN conda update conda

RUN conda install --quiet --yes memory_profiler pandas requests

RUN conda config --system --add channels conda-forge

RUN conda install --quiet --yes 'notebook=5.0.*' 'jupyterhub=0.7.2' 'jupyterlab=0.18.*'  && conda clean -tipsy

RUN conda install --yes mpld3 qgrid ipywidgets && python -c "import qgrid; qgrid.nbinstall(overwrite=True)" && conda clean -tipsy

CMD ["/bin/bash"]

EOD


@go.log WARN "Creating Jupyter Hub Configuration file"
APP_COOKIE_SECRET=$(openssl rand -hex 32)
APP_PROXY_TOKEN=$(openssl rand -hex 3)


cat > $APP_CONF_DIR/users.json << EOX
# One user per line - Format:
# { "user": "username", "user_cpu": "1", "user_mem": "2G", "user_ssh_port": 10500, "user_web_port:" 10400, "user_net_mode": "BRIDGE", "user_image": "$APP_IMG", "marathon_constraints": [], "volumes": []}

EOX
sudo chown $IUSER:zeta${APP_ROLE}data $APP_CONF_DIR/users.json
sudo chmod 660 $APP_CONF_DIR/users.json

cat > $APP_CONF_DIR/jupyterhub_config.py << EOJ
# Configuration file for jupyterhub.
import os
##
#------------------------------------------------------------------------------
# Application(SingletonConfigurable) configuration
#------------------------------------------------------------------------------

## This is an application.

## The date format used by logging formatters for %(asctime)s
c.Application.log_datefmt = '%Y-%m-%d %H:%M:%S'

## The Logging format template
c.Application.log_format = '[%(name)s]%(highlevel)s %(message)s'

## Set the log level by value or name.
c.Application.log_level = 30
#------------------------------------------------------------------------------
# JupyterHub(Application) configuration
#------------------------------------------------------------------------------
## Grant admin users permission to access single-user servers.
#
#  Users should be properly informed if this is enabled.
c.JupyterHub.admin_access = False


## The base URL of the entire application
c.JupyterHub.base_url = '/'

#  The Hub should be able to resume from database state.
c.JupyterHub.cleanup_proxy = False  # set to false for Marathon
c.JupyterHub.cleanup_servers = False

## Number of days for a login cookie to be valid. Default is two weeks.
c.JupyterHub.cookie_max_age_days = 14

## The cookie secret to use to encrypt cookies.
#
#  Loaded from the JPY_COOKIE_SECRET env variable by default.
c.JupyterHub.cookie_secret = b'$APP_COOKIE_SECRET'

## url for the database. e.g. 'sqlite:///jupyterhub.sqlite'
c.JupyterHub.db_url = 'sqlite:////app/data/jupyterhub.sqlite'

## log all database transactions. This has A LOT of output
#c.JupyterHub.debug_db = False

## show debug output in configurable-http-proxy
c.JupyterHub.debug_proxy = True 

## Send JupyterHub's logs to this file.
#  
#  This will *only* include the logs of the Hub itself, not the logs of the proxy
#  or any single-user servers.
c.JupyterHub.extra_log_file = '/app/logs/jupyterhub.log'

# This culls notebook servers that have not seen proxy trafic in 4 hours (14000 seconds)
c.JupyterHub.services = [
    {
        'name': 'cull-idle',
        'admin': True,
        'command': 'python3 /app/cull-idle/cull_idle_servers.py --timeout=14000'.split(),
    }
]

c.JupyterHub.hub_ip = '0.0.0.0'

## The port for this process
c.JupyterHub.hub_port = $APP_HUB_PORT

## The public facing ip of the whole application (the proxy)
c.JupyterHub.ip = '0.0.0.0'
## The Proxy Port
c.JupyterHub.port = $APP_WEB_PORT

## The Proxy Auth token.
#
#  Loaded from the CONFIGPROXY_AUTH_TOKEN env variable by default.
c.JupyterHub.proxy_auth_token =  '$APP_PROXY_TOKEN'

## Interval (in seconds) at which to check if the proxy is running.
c.JupyterHub.proxy_check_interval = 30


## Path to SSL certificate file for the public facing interface of the proxy
#
#  Use with ssl_key
c.JupyterHub.ssl_cert = '/app/certs/srv_cert.pem'

## Path to SSL key file for the public facing interface of the proxy
#
#
#  Use with ssl_cert
c.JupyterHub.ssl_key = '/app/certs/key-no-password.pem'

#------------------------------------------------------------------------------
# Spawner(LoggingConfigurable) configuration
#------------------------------------------------------------------------------

# We are pulling from https://github.com/JohnOmernik/marathonspawner
c.JupyterHub.spawner_class = 'marathonspawner.MarathonSpawner'

## Overideable Defaults if zeta_user_file is specified.
# If no zeta_user_file is specified, spawner will attempt to use these
# If zeta_user_file is specified and A. Can't be found or B. The User can't be found in the file AND no_user_file_fail is set to False, these will still be used. Otherwise the Spawner will fail and not attempt to start
#
c.MarathonSpawner.app_image = '$APP_NOTEBOOK_IMG'
c.MarathonSpawner.marathon_constraints = []
c.MarathonSpawner.mem_limit = '2G'
c.MarathonSpawner.cpu_limit = 1
c.MarathonSpawner.user_web_port = 10400
c.MarathonSpawner.user_ssh_port = 10500
c.MarathonSpawner.network_mode = "HOST"



## app_cmd variable - the Variable that starts
## in the app_cmd variable the following variables will be replaceable
# {username} - the username of the notebook server
# {userwebport} - the port of the Jupyter Single User Server
# {usersshport} - the Port of the SSH connection on the container
#
nbcmd = 'export PATH=\$PATH:/opt/conda/bin && env && su -c \"/opt/conda/bin/jupyterhub-singleuser'
nbcoreargs="--ip=0.0.0.0"
nbuserargs="--port={userwebport} --config /home/{username}/.jupyter/jupyter_notebook_config.py --user={username} --notebook-dir=/home/{username}"
nbhubargs = "--base-url=\$JPY_BASE_URL --hub-prefix=\$JPY_HUB_PREFIX --cookie-name=\$JPY_COOKIE_NAME --hub-api-url=\$JPY_HUB_API_URL"
nbcmdend = '\" {username}'
c.MarathonSpawner.app_cmd = nbcmd + " " + nbcoreargs + " " + nbuserargs + " " + nbhubargs + nbcmdend

## The rest of the business

c.MarathonSpawner.zeta_user_file = "/app/conf/users.json"
c.MarathonSpawner.no_user_file_fail = True

# Add longer pull time to account for huge images - oh you silly data scientists and your modules
c.MarathonSpawner.start_timeout =  60 * 5

c.MarathonSpawner.app_prefix = '${APP_MAR_ID_BASE}/notebooks'

c.MarathonSpawner.ports = []  # Additional ports used if needed

c.MarathonSpawner.shared_notebook_dir = "$APP_SHARED_NOTEBOOK_DIR"
c.MarathonSpawner.marathon_host = 'http://leader.mesos:8080'
c.MarathonSpawner.hub_ip_connect = os.environ['HUB_IP_CONNECT']
c.MarathonSpawner.hub_port_connect = int(os.environ['HUB_PORT_CONNECT'])
myvols = []

myvols.append({"containerPath": "/home/{username}", "hostPath": "${CLUSTERMOUNT}/user/{username}","mode": "RW"})
myvols.append({"containerPath": "$FS_HOME", "hostPath": "$FS_HOME","mode": "RO"})
myvols.append({"containerPath": "/opt/mesosphere", "hostPath": "/opt/mesosphere","mode": "RO"})
myvols.append({"containerPath": "$CLUSTERMOUNT", "hostPath": "$CLUSTERMOUNT","mode": "RW"})

c.MarathonSpawner.volumes = myvols




#  Defaults to an empty set, in which case no user has admin access.
c.Authenticator.admin_users = {'$APP_ADMIN_USER'}

# Authenticator to use
c.JupyterHub.authenticator_class = 'jupyterhub.auth.PAMAuthenticator'
## The name of the PAM service to use for authentication
c.PAMAuthenticator.service = 'login'

EOJ

sudo chown $IUSER:$IUSER $APP_CONF_DIR/jupyterhub_config.py
sudo chmod 770 $APP_CONF_DIR/jupyterhub_config.py


@go.log WARN "Creating Marathon File"
cat > $APP_MAR_FILE << EOL
{
  "id": "${APP_MAR_ID}",
  "cmd": "jupyterhub -f /app/conf/jupyterhub_config.py",
  "cpus": ${APP_CPU},
  "mem": ${APP_MEM},
  "instances": 1,
  "labels": {
   $APP_HA_PROXY
   "CONTAINERIZER":"Docker"
  },
  "env": {
    "HUB_IP_CONNECT": "$CN_GUESS",
    "HUB_PORT_CONNECT": "$APP_HUB_PORT"
  },
  $APP_PORT_LIST
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "${APP_IMG}",
      "network": "BRIDGE",
      "portMappings": [
        $APP_HUB_PORT_JSON,
        $APP_WEB_PORT_JSON
      ]
    },
    "volumes": [
      { "containerPath": "/app/conf", "hostPath": "${APP_CONF_DIR}", "mode": "RW" },
      { "containerPath": "/app/data", "hostPath": "${APP_DATA_DIR}", "mode": "RW" },
      { "containerPath": "/app/logs", "hostPath": "${APP_LOG_DIR}", "mode": "RW" },
      { "containerPath": "/app/certs", "hostPath": "${APP_CERT_LOC}", "mode": "RW" }
    ]

  }
}
EOL

@go.log WARN "Running $APP_HOME/adduser.sh - Please add user $APP_ADMIN_USER"
$APP_HOME/adduser.sh

##########
# Provide instructions for next steps
echo ""
echo ""
echo "$APP_NAME instance ${APP_ID} installed at ${APP_HOME} and ready to go"
echo "To start please run: "
echo ""
echo "$ ./zeta package start ${APP_HOME}/$APP_ID.conf"
echo ""


