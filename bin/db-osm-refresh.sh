# NOTE: order is important here ... db-build-osmcarto depends on data in db-build
echo "START > > > > > "
date
nohup ~/OsmLoader/bin/db-build.sh
nohup ~/OsmLoader/bin/db-build-osmcarto.sh
nohup ~/OsmLoader/bin/db-dump.sh $*
date
echo "END < < < < < "
