#!/bin/bash

# To run the maprlibrdkafka you MUST pass the client location  (/opt/mapr) to /opt/mapr ro 

IMG="dockerregv2-shared.marathon.slave.mesos:5005/maprlibrdkafka:1.0.0"


MAPR="-v=/opt/mapr:/opt/mapr:ro"

CMD="/bin/bash"


sudo docker run -it --rm $MAPR $IMG $CMD
