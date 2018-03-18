#!/bin/bash

function printBashUsage {
  echo "Usage:"
  echo "-h | --help: display this message"
  echo "-o | --osm-file: OSM file in the input to use for the initial import (must be download here: https://download.geofabrik.de/). Default: None"
  echo "-t | --tiger: use the zip files in the tiger folder in the input. Default: false"
  echo "-u | --update: url used for updating the OSM data in the postgresql db. Default: None"
}

TIGER=false
while [ ! -z $1 ]; do
  case $1 in
    -h|--help) printBashUsage
      exit 0;;
    -o|--osm-file) OSM_FILE=$2; shift 2;;
    -t|--tiger) TIGER=true; shift 1;;
    -u|--update) UPDATE_URL=$2; shift 2;;
    -*|--*) echo "Option unknown: $1"
      printBashUsage
      exit 2;;
    *) echo "Cannot parse this argument: $1"
      printBashUsage
      exit 2;;
  esac
done

LOCAL_SETTINGS="/nominatim/build/settings/local.php"

# move to the util folder
cd /nominatim/build/utils

# import data if needed
if [ ! -z $OSM_FILE ]; then
  echo "Importing OSM file $OSM_FILE ..."
  ./setup.php --osm-file /data/$OSM_FILE --all
  echo "OSM file $OSM_FILE imported"
fi

# import tiger data
if [ $TIGER = "true" ]; then
  echo "Importing TIGER data ..."
  ./imports.php --parse-tiger /data/tiger/
  ./setup.php --import-tiger-data
  # add use tiger option in needed
  if [ -z $(grep "'CONST_Use_US_Tiger_Data', true" $LOCAL_SETTINGS) ]; then
    echo "@define('CONST_Use_US_Tiger_Data', true);" >> $LOCAL_SETTINGS
  fi
  ./setup.php --create-functions --enable-diff-updates --create-partition-functions
  echo "TIGER data imported"
fi

# add auto updates
if [ ! -z $UPDATE_URL ]; then
  if [ -z $(grep "'CONST_Replication_Url', '$UPDATE_URL'" $LOCAL_SETTINGS) ]; then
    echo "// base URL of the replication service
@define('CONST_Replication_Url', '$UPDATE_URL');
// How often upstream publishes diffs
@define('CONST_Replication_Update_Interval', '86400');
// How long to sleep if no update found yet
@define('CONST_Replication_Recheck_Interval', '900');" >> $LOCAL_SETTINGS
  fi
  ./update.php --init-updates
  ./update.php --import-osmosis-all &
fi

# start the apache server
apachectl -DFOREGROUND
