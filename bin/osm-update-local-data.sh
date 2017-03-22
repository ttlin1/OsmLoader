echo "Start >>>>>"
date

. ~/OsmLoader/bin/db-common.sh

HOME=${HOME:=/home/otp}
OR_WA=${OR_WA:=${HOME}/OsmData/or-wa.osm}
OR_WA_PBF=${OR_WA_PBF:=${HOME}/OsmData/or-wa.pbf}
UPDATED_OR_WA=${UPDATED_OR_WA:=${HOME}/OsmData/or-wa_update_temp.pbf}
OSMCONVERT=${OSMCONVERT:=${HOME}/OsmLoader/osmupdate/osmconvert}
OSMUPDATE=${OSMUPDATE:=${HOME}/OsmLoader/osmupdate/osmupdate}

# Expect top, bottom, left, right variables to be defined via db-common.sh
update_osm_pbf()
{
    # Create a variable to track the number of times the update has been attempted
    tries=1

    # osmupdate can't find osmconvert unless it is run from the directory below
    echo "cd ${HOME}/OsmLoader/osmupdate"
    cd ${HOME}/OsmLoader/osmupdate

    # The osmupdate process is within a while loop because occasionally it will
    # fail due to issues with the site that hosts the changefiles, these issues
    # usually do not persist even if the process is tried again momemts later
    while [ 1 ]
    do 
        # osmupdate does not overwrite files as a precaution, so any output 
	# location must be a new file.  The --hour and --day parameters indicate
	# that only hour and day change files will be downloaded and applied to 
	# the local osm data (minute files are excluded). 
        echo "$OSMUPDATE $OR_WA_PBF $UPDATED_OR_WA \
	-v --hour --day -b=$left,$bottom,$right,$top \
	--base-url=https://planet.openstreetmap.org/replication"

        # Base url is only different from default that it uses 'https'
	time \
	$OSMUPDATE $OR_WA_PBF $UPDATED_OR_WA \
	-v --hour --day -b=$left,$bottom,$right,$top \
	--base-url=https://planet.openstreetmap.org/replication

        # If the update has succeeded or been attempted more than 5 times
	# break out of the loop
        if [ -f $UPDATED_OR_WA ] || [ $tries -gt 5 ]
        then
            break
        else
            tries_left=$(expr 5 - $tries)
            
            echo "Update process failed, will sleep for 5 minutes and try again,"
            echo "if this update fails will try $tries_left more time(s)"
            sleep 300
            
            # Increment the number of tries
            ((tries+=1))
        fi 
    done

    # Before proceeding make sure the update process has succeeded by checking for the
    # existence of the updated output file
    if [ -f $UPDATED_OR_WA ]
    then 
        # Back up the old or-wa pbf
        bkup_file $OR_WA_PBF

        # Replace the or-wa.pbf with the updated version
        echo "rm -f $OR_WA_PBF"
        rm -f $OR_WA_PBF
        echo "mv $UPDATED_OR_WA $OR_WA_PBF"
        mv $UPDATED_OR_WA $OR_WA_PBF
    else
        echo "The PBF update process seems to have failed,"
        echo "the existing PBF will be retained unmodified"
    fi

    # return to the home directory
    echo "cd $HOME"
    cd $HOME
}

# Use OSMCONVERT to convert the .pbf to an .osm file
or_wa_pbf2osm()
{
    osm_hour=$(date -r $OR_WA +%m-%d-%y_%H:00)
    pbf_hour=$(date -r $OR_WA_PBF +%m-%d-%y_%H:00)

    # or-wa.osm should only be extracted from the pbf if it doesn't yet exist or if it wasn't 
    # last modified in the same houras the pbf (the latter should mean the pbf has more recnt data)
    if [ "$osm_hour" != "$pbf_hour" ] || [ ! -f $OR_WA ]
    then
        bkup_file $OR_WA

        # Delete old or-wa.osm now that it has been backed up
        echo "rm -f $OR_WA"
        rm -f $OR_WA
        
        # Extract updated or-wa.osm from pbf
        echo "Extracting new or-wa.osm from or-wa.pbf with osmconvert"
        echo "$OSMCONVERT $OR_WA_PBF -o=$OR_WA"
        $OSMCONVERT $OR_WA_PBF -o=$OR_WA
    else
        echo "The PBF appears to be no more up-to-date than the OSM file,"
        echo "the existing OSM file be retained unmodified"
    fi
}

bkup_file()
{
    BKUP_FILE="${1}_bkup"
    
    echo "moving $BKUP_FILE to /tmp"
    mv $BKUP_FILE /tmp/
    rm -f $BKUP_FILE

    echo "copying ${1} to $BKUP_FILE"
    cp $1 $BKUP_FILE
}

update_osm_pbf;
or_wa_pbf2osm;

date
echo "End <<<<<"