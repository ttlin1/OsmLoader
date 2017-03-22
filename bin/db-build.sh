##
## PURPOSE: to load the 'osm' schema 
##
##

. ~/OsmLoader/bin/db-common.sh

function make_user()
{
    psql -p $PGPORT -d trimet -U $MASTER -c "create user $USER with password '$PASS';"
    psql -p $PGPORT -d trimet -U $MASTER -c "alter  user $USER with SUPERUSER;"

    # important for postgis to have trusted C access
    echo "UPDATE pg_language SET lanpltrusted = true WHERE lanname LIKE 'c';" | psql $PGDBNAME -U $MASTER
    echo "GRANT ALL ON LANGUAGE C to $PGUSER;" | psql $PGDBNAME -U $MASTER
    # "revoke all ON LANGUAGE C from  otp;"
}

function drop_make_schema()
{
    if [ $PGSCHEMA == "public" ]
    then
        echo "drop table nodes              cascade" | psql $PGDBNAME -U $MASTER
        echo "drop table node_tags          cascade" | psql $PGDBNAME -U $MASTER
        echo "drop table relations          cascade" | psql $PGDBNAME -U $MASTER
        echo "drop table relation_tags      cascade" | psql $PGDBNAME -U $MASTER
        echo "drop table relation_members   cascade" | psql $PGDBNAME -U $MASTER
        echo "drop table street_segments    cascade" | psql $PGDBNAME -U $MASTER
        echo "drop table streets_conflated  cascade" | psql $PGDBNAME -U $MASTER
        echo "drop table turn_restrictions  cascade" | psql $PGDBNAME -U $MASTER
        echo "drop table turns_prohibited   cascade" | psql $PGDBNAME -U $MASTER
        echo "drop table ways               cascade" | psql $PGDBNAME -U $MASTER
    else
        echo "drop schema if exists $PGSCHEMA cascade"   | psql $PGDBNAME -U $MASTER
        echo "create schema $PGSCHEMA"                   | psql $PGDBNAME -U $MASTER
        echo "grant all on schema $PGSCHEMA to $PGUSER;" | psql $PGDBNAME -U $MASTER
        echo "grant all on schema $PGSCHEMA to $MASTER;" | psql $PGDBNAME -U $MASTER
        echo "grant all on schema $PGSCHEMA to tmpublic;"| psql $PGDBNAME -U $MASTER
    fi
}


function load_osm()
{
    echo "step 1: LOADING and filtering OSM file: ${OSM_FILE}"

    # to set up the database:
    run_sql_file "${BASEDIR}/osmosis/script/pgsimple_schema_0.6.sql"
    sleep 2

    # load OR data:
    # TODO -- we permanately change the search_path variable here, and 
    # then reset (assuming just public is in the path)
    echo "ALTER USER $PGUSER SET search_path TO $PGSCHEMA,public;" \
        | psql "${PGDBNAME}" -U "${PGUSER}"
    sleep 2
    
    # Get last modification time of OSM file
    echo "Last modification of ${OSM_FILE} was:"
    stat -c %y "${OSM_FILE}"

    # via osmosis import only streets, trimet rail lines and the aerial
    # tram, the rail/tram requires drawing on route relations and 
    # trimet specific tags for the auxiliary tracks
    "${BASEDIR}/osmosis/bin/osmosis" \
    --read-xml file="${OSM_FILE}" \
    --tf reject-relations \
    --wkv keyValueListFile="${BASEDIR}/OSMSplit/keyvaluelistfile.txt" \
    --used-node \
    outPipe.0=streets+aux \
    \
    --rx file="${OSM_FILE}" \
    --tf accept-relations route=aerialway,light_rail,train,tram \
    --tf accept-relations network=TriMet operator=TriMet \
    --tf reject-ways railway=platform public_transport=platform,station \
    --used-way \
    --used-node \
    outPipe.0=rail+tram \
    \
    --merge inPipe.0=streets+aux inPipe.1=rail+tram \
    --tt "${BASEDIR}/OSMSplit/tagtransform.xml" \
    --write-pgsimp-0.6 user="${PGUSER}" password="${PGPASS}" \
        database="${PGDBNAME}"
    sleep 2
    
    echo "ALTER USER ${PGUSER} SET search_path TO public;" \
        | psql "${PGDBNAME}" -U "${PGUSER}"
}

drop_make_schema;
load_osm;

function do_splits()
{
    echo "step 2: run process.sql"
    cd $BASEDIR/OSMSplit/
    run_sql_file process.sql
    sleep 2
    cd -

    echo "step 3: rename streets"
    cd $BASEDIR/street_parser
    $PYTHON rename_streets.py
    sleep 2
    cd -

    echo "step 4: conflate.py"
    cd $BASEDIR/OSMSplit/
    $PYTHON conflate.py
    sleep 2
    cd -
}

function do_init_hastus()
{
    echo "step 5: DOING INIT..."
    cd $BASEDIR/OSMSplit/
    run_sql_file osm2init.sql
    sleep 2

    echo "step 6: DOING HASTUS..."
    run_sql_file osm2hastus.sql
    sleep 2
    cd -
}

function rename_streets()
{
    cd $BASEDIR/street_parser
    $PYTHON rename_streets.py
    sleep 2
    cd -
}

do_splits;
do_init_hastus;
grantor;

# vacuum analyze db
echo "vacuum analyze"
psql -p $PGPORT -d $PGDBNAME -U $PGUSER -c "vacuum analyze;"
