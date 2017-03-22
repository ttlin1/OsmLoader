NAME=osm2pgsql
INSTALL=~/install/${NAME}
BUILD=~/build/${NAME}
GIT=https://github.com/openstreetmap/osm2pgsql.git

function builder()
{
    if [ ! -d $BUILD ]
    then
        echo "step 00 (Parish): get latest osm2pgsql code"
        echo "git clone $GIT"
        cd  ~/build/
        git clone $GIT
    fi

    echo "step 0: update latest osm2pgsql code"
    cd $BUILD
    git pull

    echo "step 1: autoreconf"
    ./autogen.sh

    echo "step 2: config"
    configure --prefix=$INSTALL --with-geos=/home/geoserve/install/geos/bin/geos-config --with-proj=/home/geoserve/install/proj --with-postgresql=/home/geoserve/install/postgres/bin/pg_config

    echo "step 3: make "
    make

    echo "step 4: install"
    make install
}

builder
