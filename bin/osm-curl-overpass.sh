. ~/OsmLoader/bin/db-common.sh

OR_WA=${OR_WA:='or-wa.osm'}
HOME=${HOME:='/home/otp'}

#
# download OR_WA data
#
download_osm_file()
{
    while [ 1 ]
    do
       echo "==============="
       size=`ls -Hltr $OR_WA | awk -F " " '{ print $5 }'`
       if [[ $size -gt 500000000 ]]
       then
           echo "USING THE FILE " $OR_WA
           break
       fi

       # download pbf file and convert to OSM file
       echo download $OR_WA file 
       pkill -9 curl
       curl -g -o $OR_WA "http://overpass.osm.rambler.ru/cgi/xapi_meta?*[bbox=$left,$bottom,$right,$top][@meta]"

       # sleep if we get a small file
       size=`ls -Hltr $OR_WA | awk -F " " '{ print $5 }'`
       if [[ $size -lt 500000000 ]]
       then
           echo sleeping for 35 minutes and will try to download that file again
           sleep 2000
       fi

       echo "==============="
       echo ""
    done
}

#
# create read-only file (and backup) on file-share 
#
bkup_file()
{
    BKUP_FILE="${2}_${3}"
    echo  "rm -f $BKUP_FILE (mv to /tmp)"
    mv $BKUP_FILE /tmp/
    rm -f $BKUP_FILE

    echo $1 $2 $BKUP_FILE
    $1 $2 $BKUP_FILE
}

# step 1 (one X): move backup aside, copy or-wa to backup then delete or-wa (unless we 
# have a cmd-line parameter)
if [[ $# -lt 1 ]]
then
  bkup_file cp $OR_WA bkup
  echo "rm -f $OR_WA"
  rm -f $OR_WA
fi

# step 2: download osm data
download_osm_file
