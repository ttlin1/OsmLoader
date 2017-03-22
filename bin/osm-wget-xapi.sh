OR_WA=${OR_WA:='or-wa2.osm'}
OR_WA_GZ=$OR_WA.gz
BBOX=-123.4,44.8,-121.5,45.8
OSM=http://jxapi.openstreetmap.org/xapi/api/0.6/map?bbox=$BBOX
MQ_o2=http://open.mapquestapi.com/xapi/api/0.6/*[bbox=$BBOX]
MQ_OSM=http://open.mapquestapi.com/xapi/api/0.6/map?bbox=$BBOX
RU_OSM=http://jxapi.osm.rambler.ru/xapi/api/0.6/map?bbox=$BBOX

MQ=${MQ:=$MQ_OSM}

COUNT=0
while [ 1 ]
do
    for x in $MQ
    do
        COUNT=$((COUNT+1))
        echo
        echo "========= S T A R T    R U N   # $COUNT ==========="
        echo $x
        date
        rm -f $OR_WA_GZ
        wget --header="accept-encoding: gzip" $x -O $OR_WA_GZ

        echo "--------- wget done for RUN # $COUNT, now gunzip'ing the fil ---------"
        size=`ls -Hltr /home/otp/$OR_WA_GZ | awk -F" " '{ print $5 }'`
        if [[ $size -gt 10000000 ]]
        then
            echo "USING THE FILE " $OR_WA_GZ
            rm $OR_WA
            gunzip $OR_WA_GZ
            if [ $? -eq 0 ];then
                exit 0
            fi
            echo not a good zip file...will try again
            date
        fi
        echo "========= E N D   R U N   # $COUNT ==========="
        echo
        echo sleeping for 30 minutes
        sleep 1500
    done
done
