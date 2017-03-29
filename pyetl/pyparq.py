#!/usr/bin/python3
from kafka import KafkaConsumer, KafkaProducer
import json
import pandas as pd
import time
import shutil
from fastparquet import write as parqwrite
from fastparquet import ParquetFile
import os
import sys

# Variables - Should be setable by arguments at some point

envvars = {}
# envars['var'] = ['default', 'True/False Required', 'str/int']
envvars['zookeepers'] = ['', False, 'str']
envvars['app_id'] = ['', False, 'str']
envvars['bootstrap_brokers'] = ['', False, 'str']
envvars['offset_reset'] = ['earliest', False, 'str']
envvars['group_id'] = ['', True, 'str']
envvars['topic'] = ['', True, 'str']
envvars['rowmax'] = [50, False, 'int']
envvars['timemax'] = [60, False, 'int']
envvars['sizemax'] = [256000, False, 'int']
envvars['parq_offsets'] = [50000000, False, 'int']
envvars['partition_field'] = ['', True, 'str']
envvars['parq_compress'] = ['SNAPPY', False, 'str']
envvars['filemaxsize'] = [8000000, False, 'int']
envvars['uniq_env'] = ['HOSTNAME', False, 'str']
envvars['table_base'] = ['', True, 'str']
envvars['tmp_part_dir'] = ['.tmp', False, 'str']
envvars['merge_file'] = [0, False, 'int']
envvars['debug'] = [0, False, 'int']
loadedenv = {}


def main():

    global loadedenv
    loadedenv = loadenv(envvars)
    loadedenv['tmp_part'] = loadedenv['table_base'] + "/" + loadedenv['tmp_part_dir']
    loadedenv['uniq_val'] = os.environ[loadedenv['uniq_env']]
    if loadedenv['debug'] == 1:
        print(json.dumps(loadedenv, sort_keys=True, indent=4, separators=(',', ': ')))

    if not os.path.isdir(loadedenv['tmp_part']):
        os.makedirs(loadedenv['tmp_part'])

    # Get the Boostrap brokers if it doesn't exist
    if loadedenv['bootstrap_brokers'] == "":
        if loadedenv['zookeepers'] == "":
            print("Must specify either Bootstrap servers via BOOTSTRAP_BROKERS or Zookeepers via ZOOKEEPERS")
            sys.exit(1)

        mybs = boostrap_from_zk(loadedenv['zookeepers'], loadedenv['app_id'])
    if loadedenv['debug'] >= 1:
        print (mybs)

    # Create Consumer group to listen on the topic specified
    consumer = KafkaConsumer(bootstrap_servers=mybs, auto_offset_reset=loadedenv['offset_reset'], group_id=loadedenv['group_id'])
    consumer.subscribe([loadedenv['topic']])


    # Initialize counters
    rowcnt = 0
    sizecnt = 0
    lastwrite = int(time.time()) - 1
    curfile = ""
    parqar = []
    # Listen for messages
    for message in consumer:
        curtime = int(time.time())
        timedelta = curtime - lastwrite
        rowcnt += 1
        try:
            # This may not be the best way to approach this.
            val = message.value.decode('ascii', errors='replace')
        except:
            print(message.value)
            val = ""
        # Only write if we have a message
        if val != "":
            #Keep  Rough size count
            sizecnt += len(val)
            try:
                parqar.append(json.loads(val))
            except:
                print("JSON Load fail on Record fail")
            # If our row count is over the max, our size is over the max, or time delta is over the max, write the group to the parquet.
            if rowcnt >= loadedenv['rowmax'] or timedelta >= loadedenv['timemax'] or sizecnt >= loadedenv['sizemax']:

                curfile = loadedenv['uniq_val'] + "_curfile.parq"
                parqdf = pd.DataFrame.from_records([l for l in parqar])
                parts = parqdf[loadedenv['partition_field']].unique()
                if loadedenv['debug'] >= 1:
                    print("Write Dataframe to %s at %s records - Size: %s - Seconds since last write: %s - Partitions in this batch: %s" % (curfile, rowcnt, sizecnt, timedelta, parts))

                for part in parts:
                    partdf =  parqdf[parqdf[loadedenv['partition_field']] == part]
                    base_dir = loadedenv['table_base'] + "/" + part
                    final_file = base_dir + "/" + curfile
                    if not os.path.isdir('base_dir'):
                        try:
                            os.makedirs('base_dir')
                        except:
                            print("Partition Create failed, it may have been already created for %s" % (base_dir))
                    if loadedenv['debug'] >= 1:
                        print("Writing partition %s to %s" % (part, final_file))
                    if not os.path.exists(final_file):
                        parqwrite(final_file, partdf, compression=loadedenv['parq_compress'], row_group_offsets=loadedenv['parq_offsets'], has_nulls=True)
                    else:
                        parqwrite(final_file, partdf, compression=loadedenv['parq_compress'], row_group_offsets=loadedenv['parq_offsets'], has_nulls=True, append=True)

                    # Get the parquet file size and if the file size is greater than the max size , time to rotate
                    cursize =  os.path.getsize(final_file)
                    if cursize > loadedenv['filemaxsize']:
                        new_file_name = loadedenv['uniq_val'] + "_" + str(curtime) + ".parq"
                        new_file = base_dir + "/" + new_file_name
                        if loadedenv['debug'] >= 1:
                            print("Max Sized reached - %s - Writing to %s" % (cursize, new_file))
                        shutil.move(final_file, new_file)

                        # If merge_file is 1 then we read in the whole parquet file and output it in one go to eliminate all the row groups from appending
                        if loadedenv['merge_file'] == 1:
                            if loadedenv['debug'] >= 1:
                                print("Merging parqfile into to new parq file")
                            inparq = ParquetFile(new_file)
                            inparqdf = inparq.to_pandas()
                            tmp_file = loadedenv['tmp_part'] + "/" + new_file_name
                            parqwrite(tmp_file, inparqdf, compression=loadedenv['parq_compress'], row_group_offsets=loadedenv['parq_offsets'], has_nulls=True)
                            shutil.move(tmp_file, new_file)
                            inparq = None
                            inparqdf = None

                    partdf=pd.DataFrame()

                parqdf = pd.DataFrame()
                parqar =[]
                rowcnt = 0
                sizecnt = 0
                lastwrite = curtime
                curfile = ""
                time.sleep(1)

def loadenv(evars):
    print("Loading Environment Variables")
    lenv = {}
    for e in evars:
        try:
            val = os.environ[e.upper()]
        except:
            if evars[e][1] == True:
                print("ENV Variable %s is required and not provided - Exiting" % (e.upper()))
                sys.exit(1)
            else:
                print("ENV Variable %s not found, but not required, using default of '%s'" % (e.upper(), evars[e][0]))
                val = evars[e][0]
        if evars[e][2] == 'int':
            val = int(val)
        lenv[e] = val


    return lenv


# Get our bootstrap string from zookeepers if provided
def boostrap_from_zk(ZKs, app_id):
    from kazoo.client import KazooClient
    zk = KazooClient(hosts=ZKs,read_only=True)
    zk.start()

    brokers = zk.get_children('/%s/brokers/ids' % app_id)
    BSs = ""
    for x in brokers:
        res = zk.get('/%s/brokers/ids/%s' % (app_id, x))
        dj = json.loads(res[0].decode('utf-8'))
        srv = "%s:%s" % (dj['host'], dj['port'])
        if BSs == "":
            BSs = srv
        else:
            BSs = BSs + "," + srv

    zk.stop()

    zk = None
    return BSs



if __name__ == "__main__":
    main()
