. ~/OsmLoader/bin/db-common.sh

function do_init()
{
    echo "step 5: DOING INIT..."
    cd $BASEDIR/OSMSplit/
    run_sql_file osm2init.sql
    sleep 2
}

function do_hastus()
{
    echo "step 6: DOING HASTUS..."
    run_sql_file osm2hastus.sql
    sleep 2
    cd -
}

do_init;
do_hastus;
grantor;
