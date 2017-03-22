. ~/OsmLoader/bin/db-common.sh

echo "START > > > > > "
date


# if a command line parameter is passed run the init & hastus builders, if not simple export the
# init and hastus tables to shapefile and csv
if [ $1 ]
then
  echo "****** REFRESH and RELOAD THE INIT / HASTUS DATA in POSTGIS ******"
  . ~/OsmLoader/bin/db-inithastus.sh
else
  echo
  echo "******  IMPORTANT: USING THE EXISTING INIT / HASTUS DATA and JUST EXPORTING THE .shp FILES!!!! *******"
  echo
fi

# config
PGBIN=${PGBIN:="/home/geoserve/postgres/bin"}
PGSQL2SHP=${PGSQL2SHP:="$PGBIN/pgsql2shp"}
PSQL=${PSQL:="$PGBIN/psql"}
INIT_DIR=${INIT_DIR:="/home/otp/htdocs/init"}
HASTUS_DIR=${HASTUS_DIR:="/home/otp/htdocs/hastus"}
TRAPEZE_DIR=${TRAPEZE_DIR:="/home/otp/htdocs/trapeze"}


# do INIT
#
# Export the four files! (streets.shp, turnrestrictions.csv, citydirectory.shp, and streetdirectory.csv)
# All files should be in projection 4326 and INIT needs column names
# on shapefiles to be all upper case (thus no -k parameter)
echo "export INIT .shp files to $INIT_DIR"
$PGSQL2SHP -u geoserve -f $INIT_DIR/Streets.shp trimet osm.init_streets
$PGSQL2SHP -u geoserve -f $INIT_DIR/StreetDirectory.shp trimet osm.init_street_dir
$PGSQL2SHP -u geoserve -f $INIT_DIR/CityDirectory.shp trimet osm.init_city_dir

# turn.csv
tr_file="$INIT_DIR/TurnRestrictions.csv"
tr_copy_sql="COPY (SELECT * FROM osm.init_turns) TO '$tr_file' CSV;"
echo "$tr_copy_sql"
$PSQL -U geoserve -d trimet -c "$tr_copy_sql"

# zip them up ...
cd $INIT_DIR
rm -f init.zip *~
zip init.zip *.* -x *.html *.log
date_file
cd -



# do HASTUS
#
# pgsql2shp -h maps7 -u tmpublic -P tmpublic -f C:\TEMP\hastus_streets.shp trimet osm.hastus_streets
# hastus_turns as a CSV for their turn restrictions. 
# They don.t want the headers or the first column, so something like:
# COPY (SELECT from_segment, fseg_position, to_segment FROM osm.hastus_turns) TO '/home/bh/otp/osm-loader/hastus_turns.csv' CSV;

echo "export HASTUS .shp files to $HASTUS_DIR"
$PGSQL2SHP -k -u geoserve -f $HASTUS_DIR/hastus_transit.shp trimet osm.hastus_transit

# turn .csv
tr_file="$HASTUS_DIR/hastus_turns.csv"
ht_copy_sql="COPY (SELECT from_segment, fseg_position, to_segment FROM osm.hastus_turns) TO '$tr_file' CSV;"
echo "$ht_copy_sql"
$PSQL -U geoserve -d trimet -c "$ht_copy_sql"

# zip them up ...
cd $HASTUS_DIR
rm -f hastus.zip *~
zip hastus.zip *.* -x *.html *.log
date_file
cd -



# do Trapeze
echo "Export TRAPEZE shapefile to $TRAPEZE_DIR"
$PGSQL2SHP -k -u geoserve -f $TRAPEZE_DIR/trapeze_streets.shp trimet osm.trapeze_streets

# zip..
cd $TRAPEZE_DIR
rm -f trapeze.zip *~
zip trapeze.zip *.* -x *.html *.log
date_file
cd -

date
echo "END < < < < < "
