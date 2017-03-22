. ~/OsmLoader/bin/db-common.sh

HOME="/home/otp"
OSM_DATA="${HOME}/OsmData"
OR_WA="${OSM_DATA}/or-wa.osm"
OR_WA_PBF="${OSM_DATA}/or-wa.pbf"
GEOFABRIK_PBF="${OSM_DATA}/geofabrik_us_west.pbf"
OSMCONVERT="${HOME}/OsmLoader/osmupdate/osmconvert"
OSMOSIS=${OSMOSIS:=${HOME}/OsmLoader/osmosis/bin/osmosis}

# download PBF file of the western portion of the US from GeoFabrik
download_geofabrik_pbf()
{
    # don't download 
    AGE=${AGE:=72000}
    FILETIME=`stat -c %Y $GEOFABRIK_PBF`
    NOW=`date +%s`
    let DIFF=$NOW-$FILETIME;

    if [ $DIFF -lt $AGE ]
    then
        echo "Looks like $GEOFABRIK_PBF is newer than 20 hours (or $DIFF < $AGE seconds) ... skipping"
        echo "To force a re-download of $GEOFABRIK_PBF, export AGE=-111"
        return 
    else
        echo "Looks like $GEOFABRIK_PBF is older than 24 hours (or $DIFF > $AGE seconds) ... downloading"
        size=`ls -Hltr $GEOFABRIK_PBF | awk -F" " '{ print $5 }'`
        if [[ $size -gt 500000000 ]]
        then
            bkup_file $GEOFABRIK_PBF
        fi
    fi

    while [ 1 ]
    do
        # first pass at downloading the pbf file
        echo download $GEOFABRIK_PBF file 
        pkill -9 wget
        wget http://download.geofabrik.de/north-america/us-west-latest.osm.pbf -O $GEOFABRIK_PBF
        #TEST cp ~/OsmData/bkup/*pbf $GEOFABRIK_PBF

        # after the download check the size of the file if it is unusually small sleep
        # for a while then head back to the top of the loop and try the download again
        echo "==============="
        size=`ls -Hltr $GEOFABRIK_PBF | awk -F" " '{ print $5 }'`
        if [[ $size -gt 500000000 ]]
        then
            echo "USING THE FILE " $GEOFABRIK_PBF
            touch $GEOFABRIK_PBF
            break
        else
            echo "sleeping for 35 minutes and will try to download that file again"
            sleep 2000
        fi
        echo "==============="
        echo ""
    done
}


# USE OSMCONVERT to extract a the or-wa b-box from the geofabrik download
# expect top, bottom, left, right variables to be defined in db-common.sh sourced above
extract_or_wa_via_osmconvert()
{
    # back up the existing or-wa.pbf
    bkup_file $OR_WA_PBF

    echo "$OSMCONVERT $GEOFABRIK_PBF -b=$left,$bottom,$right,$top --drop-broken-refs -o=$OR_WA_PBF"
    $OSMCONVERT $GEOFABRIK_PBF -b=$left,$bottom,$right,$top --drop-broken-refs -o=$OR_WA_PBF
}

#
# USE OSMOSIS to extract a OR_WA file
# OLD CODE for 
#
extract_or_wa_via_osmosis()
{
    size=`ls -Hltr $GEOFABRIK_PBF | awk -F" " '{ print $5 }'`
    if [[ $size -gt 500000000 ]]
    then
      bkup_file $OR_WA
      rm -f $OR_WA
      echo $OSMOSIS --rb $GEOFABRIK_PBF --bounding-box top=$top bottom=$bottom left=$left right=$right completeWays=true --wx $OR_WA
      $OSMOSIS --rb $GEOFABRIK_PBF --bounding-box top=$top bottom=$bottom left=$left right=$right completeWays=true --wx $OR_WA
    else
      echo "Not extracting $OR_WA, since $GEOFABRIK_PBF is too small at $size bytes in size."
    fi
}


# create read-only file (and backup) on file-share m
bkup_file()
{
    BKUP_FILE="${1}_bkup"
    
    echo "rm -f $BKUP_FILE (mv to /tmp)"
    mv $BKUP_FILE /tmp/
    rm -f $BKUP_FILE

    echo "cp $1 $BKUP_FILE"
    cp $1 $BKUP_FILE
}

# step 0: mkdir if not exists
mkdir -p ${OSM_DATA}

# step 1: download western usa pbf file
download_geofabrik_pbf

# step 2: extract the region we need from the download
if [[ $1 == osmosis* ]]
then
   extract_or_wa_via_osmosis
else
   extract_or_wa_via_osmconvert
fi