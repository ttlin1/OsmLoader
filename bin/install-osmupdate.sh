HOME="/home/otp"
O_UPDATE_FOLDER="${HOME}/OsmLoader/osmupdate"
OSMCONVERT="${O_UPDATE_FOLDER}/osmconvert"
OSMUPDATE="${O_UPDATE_FOLDER}/osmupdate"

install_osmconvert()
{
    echo "Downloading and installing osmconvert to ${O_UPDATE_FOLDER}"
    echo "wget -O - http://m.m.i24.cc/osmconvert.c | cc -x c - -lz -O3 -o $OSMCONVERT"
    wget -O - http://m.m.i24.cc/osmconvert.c | cc -x c - -lz -O3 -o $OSMCONVERT
}

install_osmupdate()
{
    echo "Downloading and installing osmupdate to ${O_UPDATE_FOLDER}"
    echo "wget -O - http://m.m.i24.cc/osmupdate.c | cc -x c - -o $OSMUPDATE"
    wget -O - http://m.m.i24.cc/osmupdate.c | cc -x c - -o $OSMUPDATE
}

remove_existing()
{
    echo "Removing existing verisons of osmconvert and osmupdate if they exist"
    echo "rm -rf $O_UPDATE_FOLDER"
    rm -rf $O_UPDATE_FOLDER
}

remove_existing;
mkdir -p ${O_UPDATE_FOLDER};
install_osmconvert;
install_osmupdate;