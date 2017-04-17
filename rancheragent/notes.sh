#!/bin/bash

#Create DB


#CREATE DATABASE IF NOT EXISTS cattle COLLATE = 'utf8_general_ci' CHARACTER SET = 'utf8';
#GRANT ALL ON cattle.* TO 'cattle'@'%' IDENTIFIED BY 'cattle';
#GRANT ALL ON cattle.* TO 'cattle'@'localhost' IDENTIFIED BY 'cattle';




IMG="dockerregv2-shared.marathon.slave.mesos:5005/rancherserver:1.5.5"
DB_HOST="192.168.0.109"
DB_PORT="30950"
DB_USER="cattle"
DB_PASS="cattle"
DB_NAME="cattle"
HOST_PORT="8080"
sudo docker run -it -p ${HOST_PORT}:8080 -p 9345:9345 $IMG \
    --db-host $DB_HOST --db-port $DB_PORT --db-user $DB_USER --db-pass $DB_PASS --db-name $DB_NAME \
    --advertise-address 192.168.0.102 --advertise-http-port $HOST_PORT




# Launch on each node in your HA cluster
#$ docker run -d --restart=unless-stopped -p 8080:8080 -p 9345:9345 rancher/server \
#     --db-host myhost.example.com --db-port 3306 --db-user username --db-pass password --db-name cattle \
#     --advertise-address <IP_of_the_Node>
