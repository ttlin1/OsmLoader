--OSMSplit to Hastus conversion
--by Grant Humphries, Melelani Sax-Barnett, Frank Purcell for TriMet, 2012-2014

--- STEP I:  ****** SQL for hastus_transit ******

--1) Create table 'hastus_transit'
drop table if exists osm.hastus_transit cascade;
create table osm.hastus_transit (
	geom GEOMETRY,
	way_id bigint references osm.ways,
	osm_f_node bigint references osm.nodes,
	osm_t_node bigint references osm.nodes,
	osm_name text,
	alt_name text,
	osm_type text,
	access text,
	bus text,
	psv text,
	surface text,
	construction text,
	--Fields required by Hastus are below
	fdpre text,
	fname text,
	ftype text,
	fdsuf text,
	type int,
	localid bigint primary key references osm.transit_segments,
	lcity text,
	rcity text,
	lcounty text,
	rcounty text,
	fnode_ int references osm.nodes (little_id),
	tnode_ int references osm.nodes (little_id),
	drct int,
	length numeric,
	--The four fields below are an artifact of hastus using rlis as an input they won't be populated,
	--but need to exist for the import process to work properly
	leftadd1 int,
 	rgtadd1 int,
	leftadd2 int,
	rgtadd2 int
);

--2) Create table containing osm types that are acceptable in hastus transit (ways that are of
--these types and under construction will be included as well)
create temp table accepted_osm_types(osm_type text);
insert into accepted_osm_types values
	('motorway'), 		('motorway_link'), 		('trunk'), 			('trunk_link'), 	
	('primary'), 		('primary_link'),		('secondary'), 		('secondary_link'),
	('tertiary'), 		('tertiary_link'), 		('residential'),	('residential_link'),
	('unclassified'), 	('service'), 			('living_street'),	('track'),
	('road'),			('light_rail'),			('tram'), 			('rail'),
	('cable_car');

--3) Populate hastus_transit with data from transit_segments
insert into osm.hastus_transit (geom, way_id, osm_name, osm_f_node, osm_t_node, alt_name, osm_type, access,
		psv, bus, construction, surface, localid, fdpre, fname, ftype, fdsuf, fnode_, tnode_, drct)
	--Reproject to Oregon State Plan North
	select ST_Transform(ts.geom, 2913), ts.way_id, ts.osm_name, ts.node_from_osm, ts.node_to_osm,
		--alt_name hierachy (only one value is selected)
		coalesce(ts.ref, ts.name_1, ts.alt_name), 
		--if segment is under construction get osm type from construction field, otherwise use
		--which ever is not null from highway, railway and aerialway
		case when ts.highway = 'construction' or ts.railway = 'construction'
				then coalesce(ts.construction, 'road')
			else coalesce(ts.highway, ts.railway, ts.aerialway) end,
		ts.access, ts.psv, ts.bus, 
		--change value of construction field to 'yes' or 'minor' since other pertinent values have
		--been transfered to osm_type
		case when ts.construction = 'minor' then ts.construction
			when ts.construction is not null then 'yes' end,
		ts.surface, ts.id, ts.prefix, coalesce(ts.name, 'unnamed'), ts.type, ts.suffix,
		ts.node_from_little, ts.node_to_little,
		--oneway logic, refer first to oneway_bus and oneway_psv tags as they override other inputs
		--junction-roundabout implies oneway in the direction of the segment
		case when ts.oneway_bus in ('no', 'false', '0') or ts.oneway_psv in ('no', 'false', '0') then 0
			when ts.oneway_bus in ('yes', 'true', '1') or ts.oneway_psv in ('yes', 'true', '1') then 2
			when ts.oneway_bus in ('-1', 'reverse') or ts.oneway_psv in ('-1', 'reverse') then 3
			when ts.oneway in ('yes', 'true', '1') or ts.junction = 'roundabout' then 2
			when ts.oneway in ('-1', 'reverse') then 3
			else 0 end
	from osm.transit_segments ts
	--the geometry of envelope below is in wgs84, this matches the projection of the street segments table
	--but note that the geometry is being reprojected in Oregon State Plane North in the hastus_transit table.
	--Also the && operator only checks if two objects bounding boxes intersect, but it is quicker than a true
	--intersection comparison and that level of precision is fine in this case.  The smaller bounding box
	--created is a hastus requirement, coordinate order is left, bottom, right, top
	where ts.geom && ST_MakeEnvelope(-123.2, 45.2, -122.2, 45.7, 4326)
		--exclude service and dirt roads...
		and (((ts.highway not in ('service', 'living_street', 'track') or ts.highway is null)
				--and service and dirt roads that are under construction...
				and ((ts.highway != 'construction' or ts.highway is null)
					or (ts.construction not in ('service', 'living_street', 'track') or ts.construction is null))
				--and road prohibited roads..
				and (ts.access != 'no' or ts.access is null))
			--unless they explicitly allow access to transit
			or ts.bus in ('yes', 'designated')
			or ts.psv in ('yes', 'designated'))
		--exlude segments that specifically prohibit transit
		and (ts.bus != 'no' or ts.bus is null)
		and (ts.psv != 'no' or ts.psv is null)
		--exclude ways that under construction and are not passable by transit vehicles
		and ((ts.highway != 'construction' or ts.highway is null)
			or (ts.construction in (select * from accepted_osm_types) or ts.construction is null));

drop table accepted_osm_types cascade;

--Note that an index is automatically assigned to 'localid' when it is set as the primary key,
--the index below will be used to speed the following insert
drop index if exists osm.hastus_transit_osm_type_ix cascade;
create index hastus_transit_osm_type_ix on osm.hastus_transit using BTREE (osm_type);

--Clean up table to improve performance, its good idea to run this every time there's a significant changes to a
--table such as bulk inserts or the addition of indices
vacuum analyze osm.hastus_transit;

--4) Populate fields that were not easily drawn from transit segments
--Set 'type' code based on the osm_type
update osm.hastus_transit set type = case 
	when osm_type = 'motorway' then 1110
	when osm_type = 'motorway_link' then 1120
	when osm_type in ('trunk', 'primary') then 1300
	when osm_type in ('trunk_link', 'primary_link') then 1320
	when osm_type = 'secondary' then 1400
	when osm_type = 'secondary_link' then 1420
	when osm_type = 'tertiary' then 1450
	when osm_type = 'tertiary_link' then 1470
	when osm_type in ('residential', 'unclassified', 'road') then 1500
	when osm_type = 'residential_link' then 1520
	when osm_type in ('service', 'living_street') then 1800
	when osm_type in ('light_rail', 'tram', 'rail', 'cable_car') then 2200 end;

--5) Calculate the length of each segment
update osm.hastus_transit set length = ST_Length(geom);

--Optimize after recent inserts
vacuum analyze osm.hastus_transit;

--6) Get city and county information
--a. Create two temporary tables one holding the geometry of the right-most point of the two segment endpoints and the 
--other holding the left-most endpoint
create temp table left_nodes as 
	select localid,
		case 
			--Note that x-coordinate of the oregon state plane north projection becomes larger as you
			--move left to right, thus the logic below
			when ST_X(ST_StartPoint(geom)) < ST_X(ST_EndPoint(geom)) then ST_StartPoint(geom)
			else ST_EndPoint(geom)
		end as geom
	from osm.hastus_transit;

create temp table right_nodes as 
	select localid,
		case 
			when ST_X(ST_StartPoint(geom)) > ST_X(ST_EndPoint(geom)) then ST_StartPoint(geom)
			else ST_EndPoint(geom)
		end as geom
	from osm.hastus_transit;

--b.  Takes steps to improve perfomance of matching between segment end points and city/county polygons
--Add indices to new tables to improve performance on upcoming comparisons
drop index if exists left_nodes_gix cascade;
create index left_nodes_gix on left_nodes using GIST (geom);

drop index if exists left_nodes_id_ix cascade;
create index left_nodes_id_ix on left_nodes using BTREE (localid);

drop index if exists right_nodes_gix cascade;
create index right_nodes_gix on right_nodes using GIST (geom);

drop index if exists right_nodes_id_ix cascade;
create index right_nodes_id_ix on right_nodes using BTREE (localid);

--Cluster the geometry, vacuum and analyze to improve performance, vacuum only need be run when a new index
--is created (just use analyze if only clustering)
cluster left_nodes using left_nodes_gix;
vacuum analyze left_nodes;

cluster right_nodes using right_nodes_gix;
vacuum analyze right_nodes;

--c. Create tables containing mappings from city and county full names to Hastus abbreviations
create temp table city_abbreviations (full_name text, abbrev_name text);
insert into city_abbreviations values
	('Banks', 'BANK'), 			('Barlow', 'BAR'), 			('Beaverton', 'BEAV'), 
	('Camas', 'CAM'), 			('Canby', 'CNBY'),			('Carlton', 'CARL'),
	('Cornelius', 'CORN'),		('Damascus', 'DAM'), 		('Dayton', 'DAYT'),
	('Dundee', 'DUN'),			('Durham', 'DUR'),			('Estacada', 'ESTA'),
	('Fairview', 'FRVW'),		('Forest Grove', 'FRGV'),	('Gaston', 'GAST'),
	('Gladstone', 'GLAD'),		('Gresham', 'GRSM'),		('Happy Valley', 'HVLY'),
	('Hillsboro', 'HILL'),		('Johnson City', 'JHNC'),	('King City', 'KING'),
	('Lake Oswego', 'LKOS'),	('Lafayette', 'LAFY'),		('Maywood Park', 'MYDP'),
	('Milwaukie', 'MLWK'),		('Newberg', 'NEWB'),		('North Plains', 'NRPL'),
	('Oregon City', 'ORC'),		('Portland', 'PORT'),		('Rivergrove', 'RVG'),
	('Sandy', 'SNDY'),			('Sherwood', 'SHER'),		('Tigard', 'TIG'),
	('Troutdale', 'TRO'),		('Tualatin', 'TUAL'),		('Vancouver', 'VAN'),
	('Washougal', 'WGAL'),		('West Linn', 'WLNN'),		('Wilsonville', 'WILS'),
	('Wood Village', 'WVLG'),	('Yamhill', 'YAMH');

create temp table co_abbreviations (full_name text, abbrev_name text);
insert into co_abbreviations values
	('Clackamas', 'CLAC'),
	('Clark', 'CLAR'),
	('Marion', 'MARI'),
	('Multnomah', 'MULT'),
	('Skamania', 'SKAM'),
	('Washington', 'WASH'),
	('Yamhill', 'YAMH');

--Add indices to improve performance upcoming comparisons
drop index if exists city_abbrev_fname_ix cascade;
create index city_abbrev_fname_ix on city_abbreviations using BTREE (full_name);

drop index if exists co_abbrev_fname_ix cascade;
create index co_abbrev_fname_ix on co_abbreviations using BTREE (full_name);

--d. Find the city and county that the right and left end point nodes of each street segment fall within and use the
--abbreviation tables to return the shortened name of those regions in the appropriate column
update osm.hastus_transit as ht set lcity = 
	coalesce((select cab.abbrev_name from city_abbreviations cab where cab.full_name = cty.name), cty.name)
	from prod.city cty, left_nodes ln
	where ln.localid = ht.localid
		and ST_Within(ln.geom, cty.geom);

update osm.hastus_transit as ht set rcity = 
	coalesce((select cab.abbrev_name from city_abbreviations cab where cab.full_name = cty.name), cty.name)
	from prod.city cty, right_nodes rn
	where rn.localid = ht.localid
		and ST_Within(rn.geom, cty.geom);

update osm.hastus_transit as ht set lcounty = 
	coalesce((select cab.abbrev_name from co_abbreviations cab where cab.full_name = co.name), co.name)
	from prod.county co, left_nodes ln
	where ln.localid = ht.localid
		and ST_Within(ln.geom, co.geom);

update osm.hastus_transit as ht set rcounty = 
	coalesce((select cab.abbrev_name from co_abbreviations cab where cab.full_name = co.name), co.name)
	from prod.county co, right_nodes rn
	where rn.localid = ht.localid
		and ST_Within(rn.geom, co.geom);


--7) Clean up
--a. drop temp tables (cascade will also drop any indices on them)
drop table left_nodes cascade;
drop table right_nodes cascade;
drop table city_abbreviations cascade;
drop table co_abbreviations cascade;

--b. Ensure spatial constraints on geometry column
select Populate_Geometry_Columns('osm.hastus_transit'::regclass); 



--- STEP II:  ****** SQL for turns_prohibited to hastus_turns conversion ******

--Explanation of schema for Hastus Turn Restrictions:
--Hastus turn has three elements, that must be in the order that follows:
--*) ID. Identifier of the street segment having a turning restriction (this is the 'from' segment)
--*) Extremity. Extremity of the street segment having a turning restriction (this identifies the 'via' node)
   --Values:
   --• 'R': at the origin of the street segment (Reference)
   --• 'N': at the destination of the street segment (Non reference)
--*) Restricted_ID. Identifier of the street segment towards which the restriction applies ('to' segment)

--1) Create a new table, hastus_turns that indicates turn restrictions in a format that Hastus can read
drop table if exists osm.hastus_turns cascade;
create table osm.hastus_turns with oids as
	select tp.segment_from as from_segment, 
	--Determine from-segment position (set to 'R' if via node is at the start of the from segment, and 'N' if the
	--via node at the end of the from segment)
	case
		when tp.node_osm = ts.node_from_osm then 'R'
		when tp.node_osm = ts.node_to_osm then 'N'
	end as fseg_position,
	tp.segment_to as to_segment
	from osm.turns_prohibited tp, osm.transit_segments ts
	where tp.segment_from in (select localid from osm.hastus_transit)
		and tp.segment_to in (select localid from osm.hastus_transit)
		--The street segments table is joined based on from-segment so that information about its to- and
		--from-nodes can be accessed 
		and tp.segment_from = ts.id;

--Hastus conversion is complete, export hastus_transit to shapefile and hastus_turns to csv
--Ran in 744,545 ms on 4/8/14

--Also hastus can cannot have a node that is a part of more than 8 ways, this is uncommon, but use the query below
--to check for this.  If a node has more than 6 protruding segments it is almost certainly some type of data error
--so the query is also useful for finding these sorts of things:
/*select wn1.node_id,
sum(case
	when wn1.sequence_id = 0 then 1
	when wn1.sequence_id = (select max(wn2.sequence_id) from osm.way_nodes wn2 where wn1.way_id = wn2.way_id) then 1
	else 2
end) as seg_count
from osm.way_nodes wn1
where wn1.node_id in (select node_id from osm.way_nodes group by node_id having count(*) > 3)
group by node_id
order by seg_count desc;*/