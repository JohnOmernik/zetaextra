#!/bin/bash

###############
# $APP Specific
echo "The next step will walk through instance defaults for ${APP_ID}"
echo ""
read -e -p "Please enter the CPU shares to use with $APP_NAME: " -i "1.0" APP_CPU
echo ""
read -e -p "Please enter the Marathon Memory limit to use with $APP_NAME: " -i "1024" APP_MEM
echo ""
read -e -p "How many instances of $APP_NAME do you wish to run (this should match the partitions you will be working against): " -i "1" APP_CNT
echo ""
read -e -p "What user should we run $APP_NAME as: " -i "zetasvc${APP_ROLE}" APP_USER
echo ""

#############
# install specific
read -e -p "Please enter the Kafka APP_ID to use to load brokers: " APP_KAFKA_APP_ID
echo ""
read -e -p "Please confirm the Zookeeper String: " -i "$ZETA_ZKS" APP_ZKS
echo ""
read -e -p "Please enter the topic to subscribe to: " APP_KAFKA_TOPIC
echo ""
read -e -p "Please enter the table name to put the data in: " -i "mytable" APP_TABLE
echo ""
read -e -p "Please enter the location to mount to /app/data in the container (the table dir will be made in /app/data/$APP_TABLE): " -i "/zeta/$CLUSTERNAME/data/$APP_ROLE" APP_TABLE_BASE
echo ""
read -e -p "Please enter the field in your data you wish to use as a partition field: " -i "day" APP_PART


APP_MAR_FILE="${APP_HOME}/marathon.json"
APP_BIN_DIR="${APP_HOME}/bin"
APP_DATA_DIR="$APP_TABLE_BASE"
mkdir -p $APP_BIN_DIR
sudo chown -R $APP_USER:$IUSER $APP_BIN_DIR

APP_ENV_FILE="$CLUSTERMOUNT/zeta/kstore/env/env_${APP_ROLE}/${APP_NAME}_${APP_ID}.sh"

if [ -d "$APP_DATA_DIR/$APP_TABLE" ]; then
    @go.log WARN "Data directory already exists, do you wish to go on with install?"
    read -e -p "Go on with install (potentially clobbering data?)(Y/N): " -i "N" APP_GO
    if [ "$APP_GO" != "Y" ]; then
        @go.log FATAL "Wisely Exiting"
    else
        @go.log WARN "Going to use existing directory, please understand what you are doing"
    fi
fi

mkdir -p $APP_DATA_DIR/$APP_TABLE
sudo chown -R $IUSER:zeta${APP_ROLE}data $APP_DATA_DIR/$APP_TABLE
sudo chmod 770 $APP_DATA_DIR/${APP_TABLE}

cat >> $APP_BIN_DIR/pyetl.sh << EOF
#!/bin/bash

# You must provide Bootstrap servers (kafka nodes and their ports OR Zookeepers and the kafka ID of the chroot for your kafka instance
export ZOOKEEPERS="$APP_ZKS"
export KAFKA_ID="$APP_KAFKA_APP_ID"
# OR
# export BOOTSTRAP_BROKERS="node1:9000,node2:9000"

# This is the name of the consumer group your client will create/join. If you are running multiple instances this is great, name them the same and Kafka will partition the info 
export GROUP_ID="pyetl_${APP_KAFKA_TOPIC}_group"

# When registering a consumer group, do you want to start at the first data in the queue (earliest) or the last (latest)
export OFFSET_RESET="earliest"

# The Topic to connect to
export TOPIC="$APP_KAFKA_TOPIC"

# The next three items has to do with the cacheing of records. As this come off the kafka queue, we store them in a list to keep from making smallish writes and dataframes
# These are very small/conservative, you should be able to increase, but we need to do testing at volume

export ROWMAX=500 # Total max records cached. Regardless of size, once the number of records hits this number, the next record will cause a flush and write to parquet
export SIZEMAX=256000  # Total size of records. This is a rough running size of records in bytes. Once the total hits this size, the next record will cause a flush and write to parquet
export TIMEMAX=60  # seconds since last write to force a write # The number of seconds since the last flush. Once this has been met, the next record from KAfka will cause a flush and write. 

# This is the max size of (records) of a row group in a single Parquet write. If a single write exceeds this, another row group will be created in the file
export PARQ_OFFSETS=50000000

# What compression the Parquet file will be written with
export PARQ_COMPRESS="SNAPPY"

# As cached records are flush and appeneded to the current file, the file grows. This is the maximum size in bytes that the file will get. When it's reached, pyetl will create a new file
export FILEMAXSIZE=8000000
# Each individual append creates a row group. So if you have small appends, you could have lots of row groups in a single file which is inefficient. If you set this to 1, then
# pyetl will, when the max file size is reached, read the WHOLE file into a dataframe and write it back out.  If the number of records is below PARQ_OFFSETS then there will only be
# one row group making subsequent reads faster. We've only tested this on smallish files, needs some modeling to test. 
export MERGE_FILE=1

# Since we can have multiple pyetl instances running (partitions/consumer groups etc) We need some sort of uniq value so when writing file names, we don't clobber multiple instance
# files.  This is easy if you are running in Docker, using Bridged networking. We just use the HOSTNAME env variable.  If you are not running in  Docker, or you are running in host network mode
# where you could have multiple instances have the same HOSTNAME. Please set another ENV variable that is uniq. For example, you could set and ENV variable named MYSTRING to be
# export MYSTRING=\$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
# and you would run pyetl with export UNIQ_ENV="MYSTRING" instead. This ensures a lack of clobbering of files. 
export UNIQ_ENV="HOSTNAME"

# This is where you want to write the parquet files.  /app/data should be volume mounted outside your container, and then next level should be your table name
export TABLE_BASE="/app/data/${APP_TABLE}"

# This is the field in your json data that will be used to directory partition the fields. So if you provide a path  of /app/data/mytable, then the values of this field will be the directory
# names and all records with the that field having a X value will be written to X directory
export PARTITION_FIELD="$APP_PART"

# This is the loop timeout, so that when this time is reached, it will cause the loop to occur (checking for older files etc)
export LOOP_TIMEOUT="5.0"

# If a partition was appended created or appended too, and there just any more data. pyetl keeps track of the last write. Of course if a file gets over FILEMAXSIZE it will merge but sometimes a partition will just be written without
# merging. So let's say you had a file with 255mb of data and you set your FILEMAXSIZE to 256mb.  Well if you have written to the partition but have not seen any writes for 600 seconds, then merge it so you do not have lots of row groups
export PARTMAXAGE=10

# This is where tmp files our written during a merge.  Having the Preceding . keeps tools like Apache drill from querying it
export TMP_PART_DIR=".tmp"

# Turn on verbose logging.  For Silence export DEBUG=0
export DEBUG=0

# Write to the live output directory (This can cause query errors, but you get faster access to data) If set to 0 then it will write to the tmp directory until the file is closed, then move to main dir. 
export WRITE_LIVE=0

# Does the data have NULLs? See fastparquet docs for details
export HAS_NULLS=0

# Instead of discarding a record that fails to be made into JSON, this tries to remove teh request body (often containing binary data and the cause of the issue) and keep the require but drop the body data 
export DROP_REQ_BODY_ON_ERROR=1

# Run Py ETL!
python3 -u /app/code/pyparq.py

EOF
chmod +x $APP_BIN_DIR/pyetl.sh
echo ""
@go.log INFO "Application config written in $APP_BIN_DIR/pyetl.sh - you can edit conf settings for performance there"
echo ""




cat > $APP_MAR_FILE << EOL
{
  "id": "${APP_MAR_ID}",
  "cmd": " su -c /app/bin/pyetl.sh ${APP_USER}",
  "cpus": ${APP_CPU},
  "mem": ${APP_MEM},
  "instances": ${APP_CNT},
  "labels": {
   "CONTAINERIZER":"Docker"
  },
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "${APP_IMG}",
      "network": "BRIDGE"
    },
    "volumes": [
      { "containerPath": "/app/bin", "hostPath": "${APP_BIN_DIR}", "mode": "RW" },
      { "containerPath": "/app/data", "hostPath": "${APP_DATA_DIR}", "mode": "RW" }
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


