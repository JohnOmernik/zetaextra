#!/bin/bash

###############
# $APP Specific
echo "The next step will walk through instance defaults for ${APP_ID}"
echo ""

APP_MAR_DIR="$APP_HOME/marathon"
mkdir -p $APP_MAR_DIR

APP_BIN_DIR="$APP_HOME/bin"
mkdir -p $APP_BIN_DIR

APP_MAR_ID=""
cat > $APP_BIN_DIR/start.sh << EOLEADS
#!/bin/bash
function cleanrancher {
    echo "Marathon Requested Shutdown of Rancher Agent: Doing so"
    for X in \$(docker ps|grep rancher|grep -v rancherserver|grep -v mesos|cut -d" " -f1); do
        echo "Stopping \$X"
        docker stop \$X
    done
    echo "Now doing so again..."
    for X in \$(docker ps|grep rancher|grep -v rancherserver|cut -d" " -f1); do
        echo "Stopping \$X"
        docker stop \$X
    done

    kill -TERM \$child
    exit 0
}

trap cleanrancher SIGTERM

echo "Starting Rancher Agent and then running in Loop!"
/run.sh \$OURRANCH &
tail -f /dev/null &
child=\$!
echo "My Child is \$child"

wait "\$child"
EOLEADS

chmod +x $APP_BIN_DIR/start.sh

##########
# Provide instructions for next steps
echo ""
echo ""
echo "$APP_NAME instance ${APP_ID} installed at ${APP_HOME} and ready to go"
echo "To start please run: "
echo ""
echo "$ ./zeta package start ${APP_HOME}/$APP_ID.conf"
echo ""
