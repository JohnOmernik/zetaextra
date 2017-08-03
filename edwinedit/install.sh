#!/bin/bash

###############
# $APP Specific
echo "The next step will walk through instance defaults for ${APP_ID}"
echo ""
read -e -p "Please enter the CPU shares to use with $APP_NAME: " -i "1.0" APP_CPU
echo ""
read -e -p "Please enter the Marathon Memory limit to use with $APP_NAME: " -i "512" APP_MEM
echo ""
read -e -p "Please enter the user to run this as, this user needs access to the edwin.json file: " -i "zetaadm" APP_USER
echo ""
read -e -p "Please enter the user allowed to access this: " -i "zetasvc${APP_ROLE}" APP_WEB_USER
echo ""
read -e -p "Please enter the path to edwin to use for this: " -i "${CLUSTERMOUNT}/apps/prod/edwin_org" APP_EDWIN
echo ""

PORTSTR="CLUSTER:tcp:24444:${APP_ROLE}:${APP_ID}:Nginx SSL Port for EdwinEdit"
getport "CHKADD" "SSL port" "$SERVICES_CONF" "$PORTSTR"

if [ "$CHKADD" != "" ]; then
    getpstr "MYTYPE" "MYPROTOCOL" "APP_PORT" "MYROLE" "MYAPP_ID" "MYCOMMENTS" "$CHKADD"
    APP_PORTSTR="$CHKADD"
else
    @go.log FATAL "Failed to get Port for $APP_NAME instance $APP_ID with $PSTR"
fi
bridgeports "APP_PORT_JSON" "34000" "$APP_PORTSTR"

haproxylabel "APP_HA_PROXY" "${APP_PORTSTR}"
portslist "APP_PORT_LIST" "$APP_PORTSTR"

APP_HOSTNAME="${APP_ID}.${APP_ROLE}.marathon.slave.mesos"
APP_MAR_FILE="${APP_HOME}/marathon.json"
APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"

APP_CONF_DIR="$APP_HOME/conf"
APP_LOG_DIR="$APP_HOME/logs"
APP_SBIN_DIR="$APP_HOME/sbin"
APP_CERT_LOC="$APP_HOME/certs"

APP_API_URL="$APP_HOSTNAME:$APP_PORT"

mkdir -p $APP_CONF_DIR
sudo chown -R $APP_USER:$IUSER $APP_CONF_DIR
sudo chmod 770 $APP_CONF_DIR

mkdir -p $APP_LOG_DIR
sudo chown -R $APP_USER:$IUSER $APP_LOG_DIR
sudo chmod 770 $APP_LOG_DIR

mkdir -p $APP_SBIN_DIR
sudo chown -R $APP_USER:$IUSER $APP_SBIN_DIR
sudo chmod 770 $APP_SBIN_DIR

mkdir -p $APP_CERT_LOC
sudo chown -R $APP_USER:$IUSER $APP_CERT_LOC
sudo chmod 770 $APP_CERT_LOC

cat > $APP_ENV_FILE << EOL1
#!/bin/bash
export ZETA_${APP_NAME}_${APP_ID}_HOST="${APP_HOSTNAME}"
export ZETA_${APP_NAME}_${APP_ID}_MAIN_PORT="${APP_MAIN_PORT}"
EOL1

CN_GUESS="${APP_HOSTNAME}"

. $CLUSTERMOUNT/zeta/shared/zetaca/gen_server_cert.sh

cat > $APP_CERT_LOC/userauth << EOA
$APP_WEB_USER
EOA

cat > $APP_CONF_DIR/default << EOD
server {
    listen 34000 ssl;
    server_name         ${APP_HOSTNAME};

    ssl_certificate     /etc/nginx/certs/cert.pem;
    ssl_certificate_key /etc/nginx/certs/key-no-password.pem;
    ssl_protocols       TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    access_log /app/logs/nginx_access.log;
    error_log /app/logs/nginx_error.log;

    location / {
        auth_pam              "Super Secure";
        auth_pam_service_name "nginx";
        include uwsgi_params;
        uwsgi_pass unix:///tmp/uwsgi.sock;
    }
}

EOD

cat > $APP_SBIN_DIR/start.sh << EOS
#!/bin/bash

echo "Running as \$MYUSER"

sed -i "s/nginx/\$MYUSER/g" /etc/uwsgi/uwsgi.ini

sed -i "s/mynginx/\$MYUSER/g" /etc/supervisor/conf.d/supervisord.conf

chown -R \$MYUSER:zetaadm /etc/nginx

sed -i "s@access_log /var/log/nginx/access.log;@access_log /app/logs/nginx_main_access.log;@g" /etc/nginx/nginx.conf
sed -i "s@error_log /var/log/nginx/error.log;@error_log /app/logs/nginx_main_error.log;@g" /etc/nginx/nginx.conf
sed -i "s@pid /run/nginx.pid;@pid /var/log/nginx/nginx.pid;@g" /etc/nginx/nginx.conf

chown -R \$MYUSER:zetaadm /var/log/nginx
chown -R \$MYUSER:zetaadm /var/lib/nginx

/usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf

EOS

chmod +x $APP_SBIN_DIR/start.sh

cat > $APP_MAR_FILE << EOL
{
  "id": "${APP_MAR_ID}",
  "cmd": "/app/sbin/start.sh",
  "cpus": ${APP_CPU},
  "mem": ${APP_MEM},
  "instances": 1,
  "env": {
    "MYUSER": "$APP_USER"
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
      { "containerPath": "/app/edwin", "hostPath": "${APP_EDWIN}", "mode": "RW" },
      { "containerPath": "/etc/nginx/sites-enabled", "hostPath": "${APP_CONF_DIR}", "mode": "RW" },
      { "containerPath": "/app/sbin", "hostPath": "${APP_SBIN_DIR}", "mode": "RO" },
      { "containerPath": "/etc/nginx/certs", "hostPath": "${APP_CERT_LOC}", "mode": "RW" },
      { "containerPath": "/app/logs", "hostPath": "${APP_LOG_DIR}", "mode": "RW" }
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


