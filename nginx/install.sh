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
read -e -p "Do you wish to enable basic authentication? (Y/N): " -i "N" BASIC_AUTH
echo ""
CONF_AUTH=""

if [ "$BASIC_AUTH" == "Y" ]; then
    echo "We will ask for one username/password combo for basic authentication."
    echo "More can be added by editing the .htpasswd file located in the conf directory."
    echo ""
    read -e -p "Please enter the username to use for basic auth: " -i "admin" AUTH_USER
    echo ""
    echo "Please enter the password: "
    AUTH_PASS=$(openssl passwd -apr1)
    echo ""
    CONF_AUTH="auth_basic \"Restricted Content\";"$'\n'
    CONF_AUTH="${CONF_AUTH}auth_basic_user_file /etc/nginx/conf.d/.htpasswd;"$'\n'
fi

PORTSTR="CLUSTER:tcp:30200:${APP_ROLE}:${APP_ID}:Port for $APP_NAME $APP_ID"
getport "CHKADD" "Port for $APP_NAME $APP_ID" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME instance $APP_ID with $PSTR"
fi

APP_SUB=$(echo "$APP_MAR_ID"|sed "s@/@ @g")
APP_OUT=$(echo "$APP_SUB"| sed 's/ /\n/g' | tac | sed ':a; $!{N;ba};s/\n/ /g'|tr " " "-")


APP_API_URL="https://${APP_OUT}.marathon.slave.mesos:$APP_PORT"


APP_CONT_PORT="443"

bridgeports "APP_PORT_JSON" "$APP_CONT_PORT" "$APP_PORTSTR"
haproxylabel "APP_HA_PROXY" "${APP_PORTSTR}"
portslist "APP_PORT_LIST" "${APP_PORTSTR}"

APP_MAR_FILE="${APP_HOME}/marathon.json"
APP_CERT_LOC="$APP_HOME/certs"
APP_LOG_DIR="$APP_HOME/logs"
APP_CONF_DIR="$APP_HOME/conf"

APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"


mkdir -p $APP_LOG_DIR
mkdir -p $APP_CONF_DIR
mkdir -p $APP_CERT_LOC
sudo chmod 777 $APP_LOG_DIR
sudo chmod 770 $APP_CONF_DIR
sudo chmod 770 $APP_CERT_LOC

CN_GUESS="${APP_OUT}.marathon.slave.mesos"

. $CLUSTERMOUNT/zeta/shared/zetaca/gen_server_cert.sh

cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_PORT="${APP_PORT}"
EOL1


cat > $APP_CONF_DIR/.htpasswd << EOP
${AUTH_USER}:${AUTH_PASS}
EOP

cat > ${APP_CONF_DIR}/default.conf << EOL5
user root;
worker_processes  1;
daemon off;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;


events {
    worker_connections  1024;
}


http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;
    keepalive_timeout   70;


    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    upstream up_servers {
        server yourserver:yourport;
    }
    server {
        listen              443 ssl;
        server_name         farkingtsdblb-farkit-prod.marathon.slave.mesos;
        $CONF_AUTH

        ssl_certificate     /etc/nginx/certs/cert.pem;
        ssl_certificate_key /etc/nginx/certs/key-no-password.pem;
        ssl_protocols       TLSv1 TLSv1.1 TLSv1.2;
        ssl_ciphers         HIGH:!aNULL:!MD5;

        location / {
            proxy_pass http://up_servers;
        }

    # redirect server error pages to the static page /50x.html
        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
            root /usr/share/nginx/html;
        }
    }
}
EOL5

cat > $APP_MAR_FILE << EOL
{
  "id": "${APP_MAR_ID}",
  "cmd": "nginx -c /etc/nginx/conf.d/default.conf",
  "cpus": ${APP_CPU},
  "mem": ${APP_MEM},
  "instances": 1,
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
      { "containerPath": "/etc/nginx/conf.d", "hostPath": "${APP_CONF_DIR}", "mode": "RW" },
      { "containerPath": "/var/log/nginx", "hostPath": "${APP_LOG_DIR}", "mode": "RW" },
      { "containerPath": "/etc/nginx/certs", "hostPath": "${APP_CERT_LOC}", "mode": "RO" }
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


