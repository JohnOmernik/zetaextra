#!/bin/bash



submitstartsvc "RES" "$APP_MAR_ID" "$APP_MAR_FILE" "$MARATHON_SUBMIT"
if [ "$RES" != "0" ]; then
    @go.log WARN "$MAR_ID not started - is it already running?"
fi
echo ""

APP_PORT=$(cat $APP_ENV_FILE|grep PORT|cut -d"=" -f2|sed "s/\"//g")

echo "URL for the Hive: "
echo ""
echo "https://${APP_ID}-${APP_ROLE}.marathon.slave.mesos:$APP_PORT"
echo ""
