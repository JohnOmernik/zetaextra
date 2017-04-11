#!/bin/bash

NODES=$(ls -1 $APP_HOME|grep "node")
@go.log WARN "We stop things slowly to not irritate the Galera Monster"
for ND in $NODES;do
    MAR_ID="${APP_ROLE}/${APP_ID}/${ND}"
    MAR_FILE="${APP_HOME}/${ND}/marathon.json"
    @go.log INFO "Stopping $MAR_ID then waiting 10 seconds"
    stopsvc "RES" "$MAR_ID" "$MAR_FILE" "$MARATHON_SUBMIT"
    sleep 10
    echo ""
done
