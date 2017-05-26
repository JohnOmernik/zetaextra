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


    # IDs
    MAR_FILE="${APP_HOME}/marathon.json"
    MAR_ID="${APP_ROLE}/${APP_ID}"

    @go.log INFO "Stopping $APP_ID"
   ./zeta package stop $CONF_FILE

    @go.log INFO "Removing ENV file at $APP_ENV_FILE"
    if [ -f "$APP_ENV_FILE" ]; then
        rm $APP_ENV_FILE
    fi

    @go.log INFO "Removing Marathon Entries for Coordinators"
    ./zeta cluster marathon destroy $MAR_ID $MARATHON_SUBMIT 1


    @go.log INFO "Removing ports for $APP_ID"
    APP_STR="${APP_ROLE}:${APP_ID}"
    sed -i "/${APP_STR}/d" ${SERVICES_CONF}


    if [ "$DESTROY" == "1" ]; then
        NFSBASE="/zeta/$CLUSTERNAME"

        APP_TABLE_HDFS=$(echo "$APP_HOME"|sed "s@$NFSBASE@@")
        APP_TABLE_HDFS="${APP_TABLE_HDFS}/tables"
        VOL="${APP_DIR}.${APP_ROLE}.${APP_ID}.tables"

        @go.log WARN "Removing MapR-DB Tables for use in OpenTSDB"
        echo ""

        MAPRCLI="./zeta fs mapr maprcli -U=mapr"
        TABLES_PATH="$APP_TABLE_HDFS"

        TSDB_TABLE="$TABLES_PATH/tsdb"
        UID_TABLE="$TABLES_PATH/tsdb-uid"
        TREE_TABLE="$TABLES_PATH/tsdb-tree"
        META_TABLE="$TABLES_PATH/tsdb-meta"

        $MAPRCLI table delete -path $TSDB_TABLE
        $MAPRCLI table delete -path $UID_TABLE
        $MAPRCLI table delete -path $TREE_TABLE
        $MAPRCLI table delete -path $META_TABLE

        @go.log WARN "Removing Volume for Tables"
        fs_rmdir "RETCODE" "$APP_TABLE_HDFS"
        echo ""
        @go.log WARN "Also removing all data for app"
        sudo rm -rf $APP_HOME
    fi
    @go.log WARN "$APP_NAME instance $APP_ID unininstalled"

else
    @go.log WARN "User canceled uninstall"
fi

