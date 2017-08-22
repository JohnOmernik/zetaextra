#!/bin/bash
FS_LIB="lib${FS_PROVIDER}"
. "$_GO_USE_MODULES" $FS_LIB

DESTROY=1
if [ "$UNATTEND" == "1" ]; then
    CONFIRM="Y"
else
    echo ""
    echo "You have requested to uninstall the instance $APP_ID in role $APP_ROLE of the applicaiton $APP_NAME"
    echo "Uninstall stops the app, removes it from Marathon, and removes the ENV files for the application but leaves data/conf available"
    echo ""
    if [ "$DESTROY" == "1" ]; then
        echo ""
        echo "********************************"
        echo ""
        echo "You have also selected to destroy and delete all data for this app in addition to uninstalling from the ENV variables and marathon" 
        echo ""
        echo "This is irreversible"
        echo ""
        echo "********************************"
        echo ""
    fi

    read -e -p "Are you sure you wish to go on with this action? " -i "N" CONFIRM
fi
if [ "$CONFIRM" == "Y" ]; then

    @go.log WARN "Proceeding with uninstall of $APP_ID"
    @go.log INFO "Stopping $APP_ID"
    if [ "$APP_MAR_ID" != "" ]; then
       ./zeta package stop $CONF_FILE
    fi
    @go.log INFO "Removing ENV file at $APP_ENV_FILE"
    if [ -f "$APP_ENV_FILE" ]; then
        rm $APP_ENV_FILE
    fi
    ./zeta cluster marathon destroy $MAR_ID 1


    if [ "$DESTROY" == "1" ]; then
        . $CONF_FILE
        MAPRCLI="/home/zetaadm/homecluster/zetago/zeta fs mapr maprcli -U=mapr"
        BASEDIR="$APP_HOME"
        HDFSBASE=$(echo "$APP_HOME"|sed "s@${CLUSTERMOUNT}@@g")

        @go.log WARN "Deleting Stream!"
        $MAPRCLI stream delete -path $HDFSBASE/streams/brostreams
        VOL="${APP_DIR}.${APP_ROLE}.${APP_ID}.streams"
        MNT="${HDFSBASE}/streams"
        fs_rmdir "RETCODE" "$MNT"
        echo ""
        @go.log WARN "Also removing all data for app"
        sudo rm -rf $APP_HOME
    fi
    @go.log WARN "$APP_NAME instance $APP_ID unininstalled"

else
    @go.log WARN "User canceled uninstall"
fi
