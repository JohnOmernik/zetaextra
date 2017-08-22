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
read -e -p "Are you going to be using Edwin for your org? (Y/N): " -i "N" USE_EDWIN
echo ""
echo "If you would like to specify an Edwin Org Code Location, please do so now"
echo "This is optional, if you do not specify it, it will not change things, edwin org provides a way to share information amongst teams"
read -e -p "Please provide a path to edwin_org's code directory: " -i "" EDWIN_ORG_CODE
echo ""
read -e -p "Do you wish to blank out ENV Proxies so users can't use them? (Recommeded especially when there are passwords)(Y/N): " -i "Y" BLANK_PROXYS
echo ""
read -e -p "Do you wish to include MapR's librdkafka in the container for streaming working? (Y/N): " -i "N" MAPR_LIBRDKAFKA
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

NOTE_SUB=$(echo "$APP_MAR_ID_BASE"|sed "s@/@ @g")
NOTE_OUT=$(echo "$NOTE_SUB"| sed 's/ /\n/g' | tac | sed ':a; $!{N;ba};s/\n/ /g'|tr " " "-")


NOTE_URL_BASE="notebooks-${NOTE_OUT}.marathon.slave.mesos"


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
read -e -p "Please provide the Drill URL for the Home location specified above: " -i "https://drillprod-prod.marathon.slave.mesos:20004" APP_DRILL_URL
echo ""
read -e -p "Please provide a Spark Home location. This is the full path to the spark directory under your app instace (Likely with version bin with hadoop in the directory name): " -i "$CLUSTERMOUNT/zeta/prod/spark/sparkprod/spark-2.1.1-bin-without-hadoop" APP_SPARK
echo ""
cat > $APP_HOME/adduser.sh << EOA
#!/bin/bash
CLUSTERNAME="$CLUSTERNAME"
CLUSTERMOUNT="$CLUSTERMOUNT"
APP_ROLE="$APP_ROLE"
BLANK_PROXYS="$BLANK_PROXYS"
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
DRILL_BASE_URL="$APP_DRILL_URL"
SPARK_HOME="$APP_SPARK"
USE_EDWIN="$USE_EDWIN"
EDWIN_ORG_CODE="$EDWIN_ORG_CODE"
NOTE_URL_BASE="$NOTE_URL_BASE"
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


if [ "$MAPR_LIBRDKAFKA" == "Y" ]; then
# Source the current version of MapR 
. $_GO_ROOTDIR/vers/mapr/$MAPR_VERS

#env|sort

MAPR_CLIENT_BASE="$UBUNTU_MAPR_CLIENT_BASE"
MAPR_CLIENT_FILE="$UBUNTU_MAPR_CLIENT_FILE"
MAPR_LIBRDKAFKA_BASE="$UBUNTU_MAPR_MEP_BASE"
MAPR_LIBRDKAFKA_FILE="$UBUNTU_MAPR_LIBRDKAFKA_FILE"

DOCKER_STREAM="ENV C_INCLUDE_PATH=/opt/mapr/include"$'\n'

DOCKER_STREAM="${DOCKER_STREAM}ENV LIBRARY_PATH=/opt/mapr/lib"$'\n'
DOCKER_STREAM="${DOCKER_STREAM}ENV JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64"$'\n'
DOCKER_STREAM="${DOCKER_STREAM}ENV LD_LIBRARY_PATH=/opt/mapr/lib:\$JAVA_HOME/jre/lib/amd64/server"$'\n'
DOCKER_STREAM="${DOCKER_STREAM}RUN wget ${MAPR_CLIENT_BASE}/${MAPR_CLIENT_FILE} && wget ${MAPR_LIBRDKAFKA_BASE}/${MAPR_LIBRDKAFKA_FILE} && dpkg -i ${MAPR_CLIENT_FILE} && dpkg -i ${MAPR_LIBRDKAFKA_FILE} && rm ${MAPR_CLIENT_FILE} && rm ${MAPR_LIBRDKAFKA_FILE} && ldconfig && git clone https://github.com/confluentinc/confluent-kafka-python && cd confluent-kafka-python && /opt/conda/bin/python3 setup.py install && cd .. && rm -rf confluent-kafka-python && rm -rf /opt/mapr "$'\n'
else
    DOCKER_STREAM=""
fi


cat > $APP_BUILD_DIR/Dockerfile << EOD
FROM dockerregv2-shared.marathon.slave.mesos:5005/anaconda3:4.4.0

WORKDIR /app

RUN apt-get update && apt-get upgrade -y && apt-get install -y syslinux syslinux-utils pwgen openssh-server gcc pass libnss3 git curl && apt-get clean && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

RUN echo "root:\$(pwgen -s 16 1)" | chpasswd

RUN mkdir /var/run/sshd

RUN sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# SSH login fix. Otherwise user is kicked off after login
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

RUN echo "export LESSOPEN='| /usr/bin/lesspipe %s'" >> /etc/profile
RUN echo "export LESSCLOSE='/usr/bin/lesspipe %s %s'" >> /etc/profile
RUN echo "export LS_COLORS='rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arc=01;31:*.arj=01;31:*.taz=01;31:*.lha=01;31:*.lz4=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.tzo=01;31:*.t7z=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.dz=01;31:*.gz=01;31:*.lrz=01;31:*.lz=01;31:*.lzo=01;31:*.xz=01;31:*.bz2=01;31:*.bz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.war=01;31:*.ear=01;31:*.sar=01;31:*.rar=01;31:*.alz=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:*.cab=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.webm=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.ogv=01;35:*.ogx=01;35:*.aac=00;36:*.au=00;36:*.flac=00;36:*.m4a=00;36:*.mid=00;36:*.midi=00;36:*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:*.oga=00;36:*.opus=00;36:*.spx=00;36:*.xspf=00;36:'" >> /etc/profile

RUN sed -i "s/use_authtok //g" /etc/pam.d/common-password

RUN conda update conda

RUN conda config --system --add channels conda-forge

RUN conda install --quiet --yes memory_profiler pandas requests python-snappy python-lzo brotli pytest

RUN conda install --quiet --yes 'notebook=5.0.*' 'jupyterhub=0.7.2' 'jupyterlab=0.18.*'  && conda clean -tipsy

RUN conda install --yes mpld3 plotly requests-toolbelt findspark setuptools qgrid ipywidgets && jupyter nbextension enable --py --sys-prefix widgetsnbextension && python -c "import qgrid; qgrid.nbinstall(overwrite=True)" && conda clean -tipsy

RUN echo "PATH=\$PATH:/opt/conda/bin" >> /etc/environmennt && git clone https://github.com/johnomernik/edwin && pwd && cd edwin && python3 setup.py install

$DOCKER_STREAM

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
nbcmd = 'export PATH=\$PATH:/opt/conda/bin && sed -i "s/Port 22/Port {usersshport}/g" /etc/ssh/sshd_config && /usr/sbin/sshd && env && su -c \"/opt/conda/bin/jupyterhub-singleuser'
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
echo "Before you start though - You want to build the jupyter notebook at: $APP_HOME/Dockerbuild/build.sh"
echo ""
echo "Once that's done you want to run $APP_HOME/adduser.sh - To add $APP_ADMIN_USER"
echo ""

