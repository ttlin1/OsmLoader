export BASEDIR=${HOME}/OsmLoader
export PYTHON=${BASEDIR}/py/bin/python
export PATH="${PYTHON}:${BASEDIR}/py/bin/:.:./bin:~/OsmLoader/bin/:~/install/jdk/bin:/home/geoserve/postgres/bin/:$PATH"
export LD_LIBRARY_PATH="${BASEDIR}/bin:/home/geoserve/install/postgres/lib:/home/geoserve/install/gdal/lib:/home/geoserve/install/geos/lib"
export OSM_DUMP=osm.tar
export OSM_MIN_SIZE=10000000
export OSM_TAR_MIN_SIZE=1500000000
export OSM_DUMPER=~/OsmLoader/bin/db-dump.sh

export OSM_FILE=~/OsmLoader/or-wa.osm
export OSM_STYLE=~/OsmLoader/etc/osm2pgsql.style


#
# per jeff for Marion / Polk -- Nov 2013
# NEW: top=45.8   bottom=44.68 left=-123.8  right=-121.5
# OLD: top=45.8   bottom=44.8  left=-123.4  right=-121.5
#
export top=${top:='45.8'};
export bottom=${bottom:='44.68'};
export left=${left:='-123.8'}; 
export right=${right:='-121.5'};

function osmenv()
{
    # generic environment with public schema
    export MASTER=${MASTER:="geoserve"}
    export PGDBNAME=${PGDBNAME:="osm"}
    export PGUSER=${PGUSER:="osm"}
    export PGPASS=${PGPASS:="osm"}
    export PGPORT=${PGPORT:="5432"}
    export PGSCHEMA=${PGSCHEMA:="public"}
}
function tmenv()
{
    # trimet environment with osm schema
    export MASTER=${MASTER:="geoserve"}
    export PGDBNAME=${PGDBNAME:="trimet"}
    export PGUSER=${PGUSER:="geoserve"}
    export PGPASS=${PGPASS:="XXXXXXX"}
    export PGPORT=${PGPORT:="5432"}
    export PGSCHEMA=${PGSCHEMA:="osm"}
    export OSM_SCHEMA=${OSM_SCHEMA:="osm"}
    export CARTO_SCHEMA=${CARTO_SCHEMA:="osmcarto"}
}

#
# echo out a build date and (data) file date to 'data' file
#
# @see ~/htdocs/hastus and ~/htdocs/init, where the index.html 
#     includes this file in an iframe
#
function date_file()
{
  data_file=$1
  data_file=${data_file:="/home/otp/OsmData/or-wa.osm"}

  out_file=$2
  out_file=${out_file:="date"}

  d=`date`
  echo "Build date: $d" > $out_file
  echo >> $out_file

  fdate=`ls -ltr $data_file | awk -F" " '{ print $6,$7,$8 }'`
  echo "Data file date: $fdate"  >> $out_file
  echo >> $out_file
}

if [ $USER = "bh" ] || [ $USER = "otp" ] || [ $USER = "otp-build" ] || [ $USER = "geoserve" ]
then
    tmenv;
else
    osmenv;
fi

function grantor()
{
    schema=$PGSCHEMA
    if [ $1 ]
    then
        schema=$1
    fi

    if [ $schema != "public" ]
    then
        echo "grant all on schema $schema to $PGUSER;" | psql $PGDBNAME -U $MASTER
        echo "grant all on schema $schema to $MASTER;" | psql $PGDBNAME -U $MASTER
        echo "grant all on schema $schema to tmpublic;"| psql $PGDBNAME -U $MASTER
    fi

    for table in `echo "SELECT relname FROM pg_stat_all_tables where schemaname = '${schema}';" | psql $PGDBNAME | grep -v "relname" | grep "^ "`;
    do
	echo "GRANT ALL ON TABLE ${schema}.$table"
	echo "GRANT ALL ON TABLE ${schema}.$table to $PGUSER;"  | psql $PGDBNAME -U $MASTER
	echo "GRANT ALL ON TABLE ${schema}.$table to $MASTER;"  | psql $PGDBNAME -U $MASTER
	echo "GRANT ALL ON TABLE ${schema}.$table to tmpublic;" | psql $PGDBNAME -U $MASTER
    done
}

# runs a .sql file, but first sets schema to our schema
function run_sql_file()
{
    echo "SET search_path TO $PGSCHEMA,public; \i $1;  | psql -q -d $PGDBNAME -U $PGUSER"
    echo "SET search_path TO $PGSCHEMA,public; \i $1;" | psql -q -d $PGDBNAME -U $PGUSER
}
