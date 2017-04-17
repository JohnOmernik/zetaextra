#!/bin/bash
FS_LIB="lib${FS_PROVIDER}"
. "$_GO_USE_MODULES" $FS_LIB

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
    ./zeta package stop $CONF_FILE

    @go.log INFO "Removing ENV file at $APP_ENV_FILE"
    if [ -f "$APP_ENV_FILE" ]; then
        rm $APP_ENV_FILE
    fi

    @go.log INFO "Destroying $APP_MAR_ID in marathon"
    ./zeta cluster marathon destroy $APP_MAR_ID $MARATHON_SUBMIT 1

    @go.log INFO "Removing ports for $APP_ID"
    APP_STR="${APP_ROLE}:${APP_ID}"
    sed -i "/${APP_STR}/d" ${SERVICES_CONF}

    if [ "$DESTROY" == "1" ]; then
        @go.log WARN "Removing FS Volumes for $APP_ID"
        VOL="${APP_DIR}.${APP_ROLE}.${APP_ID}.meta"
        MNT="/${APP_DIR}/${APP_ROLE}/${APP_NAME}/${APP_ID}/meta"
        fs_rmdir "RETCODE" "$MNT"

        VOL="${APP_DIR}.${APP_ROLE}.${APP_ID}.data"
        MNT="/${APP_DIR}/${APP_ROLE}/${APP_NAME}/${APP_ID}/data"
        fs_rmdir "RETCODE" "$MNT"

        VOL="${APP_DIR}.${APP_ROLE}.${APP_ID}.wal"
        MNT="/${APP_DIR}/${APP_ROLE}/${APP_NAME}/${APP_ID}/wal"
        fs_rmdir "RETCODE" "$MNT"

        @go.log WARN "Also removing all data for app"
        sudo rm -rf $APP_HOME
    fi
    @go.log WARN "$APP_NAME instance $APP_ID unininstalled"

else
    @go.log WARN "User canceled uninstall"
fi

