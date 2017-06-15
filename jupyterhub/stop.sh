#!/bin/bash

@go.log WARN "Stopping Jupyterhub"
./zeta cluster marathon scale $APP_MAR_ID 0 1
echo ""
@go.log WARN "Waiting 5 seconds"
sleep 5
NEW_MAR_ID=$(echo "$APP_MAR_ID"|sed "s/jupyterhub/notebooks/g")

@go.log WARN "Stopping all notebooks in $NEW_MAR_ID"
NBS=$(curl -s http://marathon.mesos:8080/v2/groups/$NEW_MAR_ID|jq ".apps"|jq ".[]"|jq -r ".id")
for NB in $NBS; do
    echo "Stopping $NB"
    ./zeta cluster marathon scale "$NB" 0 1
done

