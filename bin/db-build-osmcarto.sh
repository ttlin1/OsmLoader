##
## PURPOSE: to load osm street data via the osm2pgsql application 
##          loads data into the 'osm' schema 
##
. ~/OsmLoader/bin/db-common.sh

#
# use osm2pgsql to input data into our db
#
function load_osm_data()
{
    # Get last modification time of OSM file
    echo "Last modification of $OSM_FILE was:"
    stat -c %y $OSM_FILE

    echo "STEP 1: load new OSM data into 'osm_load' tables"
    osm2pgsql -d trimet -U geoserve -p '' -S $OSM_STYLE $OSM_FILE

    echo "step 2: add id column (why? ... not sure)"
    for t in line point polygon roads 
    do 
        psql $PGDBNAME -U $MASTER -c "ALTER TABLE public._${t} ADD COLUMN id serial NOT NULL PRIMARY KEY;"
    done
}


#
# FUNCTION DOES THE FOLLOWING:
# - create new osmcart schema
# - move osm2pgsql _X tables from public schema to osmcarto schema
# - rename the streets
# - fixup various tags for rendering on the map
#
function fix_up_osm_data()
{
    echo "step 1: clear out the old carto data"
    psql $PGDBNAME -U $MASTER -c "drop schema if exists $CARTO_SCHEMA cascade;" 
    psql $PGDBNAME -U $MASTER -c "create schema $CARTO_SCHEMA;"

    echo "step 2: move the osm carto tables from 'public' to $CARTO_SCHEMA"
    for t in line point polygon roads 
    do 
        psql $PGDBNAME -U $MASTER -c "ALTER TABLE public._${t} SET SCHEMA ${CARTO_SCHEMA}"
    done

    echo "step 3: rename streets"
    sleep 2
    cd $BASEDIR/street_parser
    echo $PYTHON rename_streets.py extraneous-cmd-line-arg-for-osmcarto
    $PYTHON rename_streets.py extraneous-cmd-line-arg-for-osmcarto
    sleep 2
    cd -

    echo "step 4: change labeling permission to hide off ramps (NOTE: label boolean column added by rename_streets.py above)"
    psql $PGDBNAME -U $MASTER -c "UPDATE ${CARTO_SCHEMA}._roads SET label = FALSE WHERE highway LIKE '%link';" 
    psql $PGDBNAME -U $MASTER -c "UPDATE ${CARTO_SCHEMA}._line  SET label = FALSE WHERE highway LIKE '%link';" 
}


#
# map osm load tables to feature tables
#
function publish_carto_tables()
{
    echo "STEP A: make publish tables"
    for t in street
    do
        echo "STEP A1: make publish table $t" 
        psql $PGDBNAME -U $MASTER -f $BASEDIR/carto_tables/${t}.sql
    done

    echo "STEP B: publish / populate new tables" 
    psql $PGDBNAME -U $MASTER -f $BASEDIR/carto_tables/publish.sql
}


size=`ls -Hltr $OSM_FILE | awk -F" " '{ print $5 }'`
echo "$size of $OSM_FILE"
if [[ $size -gt 5000000 ]]
then
    echo "LOAD..."
    load_osm_data;
    fix_up_osm_data;

    echo "PUBLISH..."
    publish_carto_tables

    export PGSCHEMA=$CARTO_SCHEMA
    grantor
fi
