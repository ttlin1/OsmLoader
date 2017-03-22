--OSMSplit to INIT conversion
--Grant Humphries + Melelani Sax-Barnett + Frank Purcell for TriMet, 2012-2014

--\echo STEP I ****** SQL for transit_segments to streets.shp conversion ******

--1) Create a new table, init_streets
drop table if exists osm.init_streets cascade;
create table osm.init_streets (
	geom GEOMETRY,
	segment_id int primary key references osm.transit_segments,
	prim_name text,
	sec_name text,
	category int,
	type int,
	style int,
	one_way int,
	speed int,
	f_node int references osm.nodes (little_id),
	t_node int references osm.nodes (little_id),
	roundabout int,
	--fields below reference original osm data, not used by init, but good for debugging
	osm_way_id bigint references osm.ways,
	osm_f_node bigint references osm.nodes, 
	osm_t_node bigint references osm.nodes,
	highway text
);

--2) Populate init_streets from transit_segments
insert into osm.init_streets (geom, segment_id, prim_name, sec_name, category, type, style, one_way, speed,
		f_node, t_node, roundabout, osm_way_id, osm_f_node, osm_t_node, highway)
	select ts.geom, ts.id,
		--'prim_name' aka primary name, freeways should be called by their reference number (i.e. I-5), unnamed
		--freeway ramps should be called 'ramp', unnamed service roads should be called 'service road', all
		--other streets with an OSM tag 'name' should be called by that name, all other entries should be null
		case when ts.highway = 'motorway' and ts.ref is not null then ts.ref
			--use exit information to name freeway ramps if it exists
			when ts.highway = 'motorway_link' and (ts.exit_ref is not null or ts.exit_to is not null)
				--coalesce and regexp_replace are used to get the proper formating when exit_ref and/or
				--exit_to are null
				then regexp_replace('Exit ' || coalesce(ts.exit_ref, '') || ' to ' || coalesce(ts.exit_to, ''), ' to $', '')
 			when ts.highway = 'motorway_link' and ts.label_text is null then 'ramp'
			when ts.highway = 'service' and ts.label_text is null then 'service road'
			else ts.label_text end,
		--'sec_name' aka secondary name, the hierachy is name, ref, name_1, alt_name, only use values that are
		--not in prim_name if multiple remaining names exist separate them with forward slashes
		case when ts.highway = 'motorway' and ts.ref is not null
				then trim('/' from coalesce(ts.label_text, '') || '/' || coalesce(ts.name_1, '') || '/' || coalesce(ts.alt_name, ''))
			when coalesce(ts.ref, ts.name_1, ts.alt_name) is not null 
				--coalesce is used below to return empty strings in cases where these fields are null
				then trim('/' from coalesce(ts.ref, '') || '/' || coalesce(ts.name_1, '') || '/' || coalesce(ts.alt_name, '')) end,
		--'category' values (relevance/priority for navigation), motorway and trunk links are treated differently
		--than all other links and musrt always have a value of '2' and '3' respectively (via Frank Binder)
		case when ts.highway = 'motorway' then 1
			when ts.highway in ('trunk', 'motorway_link') then 2
			when ts.highway in ('primary', 'trunk_link') then 3
			when ts.highway = 'secondary' then 4
			when ts.highway = 'tertiary' then 5
			--zero is a place-holder value for these segments, they will be reassigned a 'category' number
			--based on segments they are contiguous to later in the script
			when ts.highway in ('primary_link', 'secondary_link', 'tertiary_link') then 0
			--if not a major street and unpaved, surface dictates the category
			when ts.surface in ('cobblestone', 'compacted', 'dirt', 'grass', 'gravel',
				'ground', 'pebblestone', 'unpaved', 'wood') then 7
			when ts.highway in ('residential', 'unclassified', 'road') then 6
			when ts.highway in ('service', 'living_street', 'track') then 7
			--again this a place-holder and segments that fall here will recieve a new value later
			when ts.highway = 'residential_link' then 0 end,
		--'type' values (estimated average speed by road type)
		case when ts.surface in ('cobblestone', 'compacted', 'dirt', 'grass', 'gravel',
				'ground', 'pebblestone', 'unpaved', 'wood') then 12 
			when ts.highway = 'motorway' then 2
			when ts.highway = 'trunk' then 3
			when ts.highway in ('trunk_link', 'primary', 'primary_link') then 4
			when ts.highway in ('secondary', 'secondary_link') then 5
			when ts.highway = 'motorway_link' then 6
			when ts.highway in ('tertiary', 'tertiary_link') then 7
			when ts.highway in ('residential', 'residential_link', 'unclassified', 'road') then 10
			when ts.highway in ('service', 'living_street', 'track') then 12 end,
		--'style' values (for cartographic appearance)
		case when ts.highway in ('motorway', 'motorway_link') then 1
			when ts.highway in ('trunk', 'trunk_link') then 2
			when ts.highway in ('primary', 'primary_link') then 3
			when ts.highway in ('secondary', 'secondary_link', 'tertiary', 'tertiary_link') then 4
			when ts.highway in ('residential', 'residential_link', 'unclassified', 'road') then 5
			when ts.highway in ('service', 'living_street', 'track') then 6 end,
		--'one_way' (controls directionality as well as access)
		--'3' access for init vehicles is denied
		case when (ts.access = 'no' 
					and (ts.bus not in ('yes', 'designated') or ts.bus is null) 
					and (ts.psv not in ('yes', 'designated') or ts.psv is null))
				or ts.bus = 'no' or ts.psv = 'no'
				--this is a special case apparently the LIFT buses can't travel over this bridge
				or ts.label_text = 'Oregon City Bridge' then 3
			--oneway:bus and oneway:psv tags are checked first because they override the standard oneway tag
			--'0' travel allowed in both directions
			when ts.oneway_bus in ('no', 'false', '0') or ts.oneway_psv in ('no', 'false', '0') then 0 
			--'1' one way street in the direction of the line segment
			when ts.oneway_bus in ('yes', 'true', '1') or ts.oneway_psv in ('yes', 'true', '1') then 1
			--'2' one way street against the direction of the segment
			when ts.oneway_bus in ('-1', 'reverse') or ts.oneway_psv in ('-1', 'reverse') then 2
			when ts.oneway in ('yes', 'true', '1') or ts.junction = 'roundabout' then 1
			when ts.oneway in ('-1', 'reverse') then 2
			else 0 end, 
		ts.node_from_little, ts.node_to_little,
		--'speed' posted speed limit in mph
		case when ts.maxspeed like '%mph%' then rtrim(ts.maxspeed, ' mph')::int
			--units other than mph are given through out the value
			when trim(ts.maxspeed) ~* '^[0-9]{1,2}[a-z ]+' then null
			--if units aren't given in the field they are assumed to be kph, those are converted to mph here
			else ts.maxspeed::int * 0.621371 end,
		--'roundabout'
		case when ts.junction = 'roundabout' then 1
			else 0 end,
		ts.way_id, ts.node_from_osm, ts.node_to_osm, ts.highway
	from osm.transit_segments ts
	--This clips larger osm export to bounding box need for init streets
	where ts.geom && ST_MakeEnvelope(-123.2, 45.2, -122.2, 45.7, 4326)
		--exclude railways, aerial trams and streets under construction
		and ts.highway is not null
		and ts.highway != 'construction';

--Add indices to improve performance, note that assigning segment_id as primary key automatically creates
--a b-tree index in that column
drop index if exists osm.init_streets_gix cascade;
create index init_streets_gix on osm.init_streets using GIST (geom);


--3) Set the 'category' value for non-freeway connector streets (aka 'links') based on the value that
--continguous non-links have
drop table if exists osm.merged_category_segs cascade;
create table osm.merged_category_segs as
	--a category value of 0 implies segments are (non-motorway) links
	select (ST_Dump(geom)).geom as geom, category
	from (select ST_LineMerge(ST_Collect(geom)) as geom, category
			from osm.init_streets
			group by category) as unioned_category_segs;

drop index if exists osm.merged_cats_gix cascade;
create index merged_cats_gix on osm.merged_category_segs using GIST (geom);

drop index if exists osm.merged_cats_category_ix cascade;
create index merged_cats_category_ix on osm.merged_category_segs using BTREE (category);

drop table if exists osm.link_category_vals cascade;
create table osm.link_category_vals as
	select mcs1.geom, case when max(mcs2.category) < 7 
		then (max(mcs2.category) + 1) else 7 end as category
	from osm.merged_category_segs mcs1, osm.merged_category_segs mcs2
	where ST_Touches(mcs1.geom, mcs2.geom)
		and mcs1.category = 0
	group by mcs1.geom;

drop index if exists osm.link_vals_gix cascade;
create index link_vals_gix on osm.link_category_vals using GIST (geom);

update osm.init_streets as ins set category = lcv.category
	from osm.link_category_vals lcv
	where ST_Contains(lcv.geom, ins.geom);

drop table osm.merged_category_segs cascade;
drop table osm.link_category_vals;

--Step 1 ran 4/12 in 355777 ms



--\echo STEP II ****** SQL for turns_prohibited to TurnRestrictions.csv conversion ******

--1) Create a new table, init_turns
drop table if exists osm.init_turns cascade;
create table osm.init_turns with oids as
	--using remapped node id here as opposed to the osm node
	select segment_from as from_segment_id, segment_to as to_segment_id, node_little as node
	from osm.turns_prohibited
	--only grab turn restriction that have both ways in the init coverage area
	where segment_to in (select distinct segment_id from osm.init_streets)
		and segment_from in (select distinct segment_id from osm.init_streets);



--\echo STEP III: ****** SQL to create CityDirectory.shp (must do before StreetDirectory.shp) ******

/*
GENERAL FORMAT:
locality_id text GID from datasets plus prefix to tell which dataset from (CTY = city, CO = county, PDXMETRO = outside)
country_id text ( = ‘USA’)
name1 = main locality text
name2 = sub locality text (skip, only applicable for more complex applications/not needed for us)
city_id = text include if part of larger thing with multiple pieces (column needed but leaving blank)
level = importance i.e. county vs. city int with 1 biggest/most relevant to 15 smallest
*/

--1) Create a new table, init_ctydir, will be made up of centroids/points for each of the cities & counties
drop table if exists osm.init_ctydir cascade;
create table osm.init_ctydir (
	geom GEOMETRY,
	locality_id text,
	country_id text,
	name1 text,
	city_id text,
	level int
) with oids;

--2) Populate fields
--a. Insert info from counties
insert into osm.init_ctydir (geom, locality_id, country_id, name1, level)
	select ST_Centroid(ST_Transform(co.geom, 4326)), 'co' || co.id, 'USA', co.name || ' County', 2
	from prod.county co;

--b. Insert info from cities
insert into osm.init_ctydir (geom, locality_id, country_id, name1, level)
	select ST_Centroid(ST_Transform(cty.geom, 4326)), 'cty' || cty.id, 'USA', cty.name, 3
	from prod.city cty;

--c. Add a row for metro area as whole
insert into osm.init_ctydir (geom, locality_id, country_id, name1, level)
	values (ST_SetSRID(ST_MakePoint(-122.661335, 45.4825716), 4326), 'metro1', 'USA', 'Portland Metropolitan Area', 1);



--\echo STEP IV  ****** SQL to create StreetDirectory.shp (must do AFTER CityDirectory.shp) ******

--1) Create a new table, init_stdir
drop table if exists osm.init_stdir cascade;
create table osm.init_stdir (
	geom GEOMETRY,
	segment_id int primary key references osm.transit_segments,
	country_id text,
	locality_id text,
	street_id text
);

--2) Insert mid of streets into street directory table
insert into osm.init_stdir (geom, segment_id, country_id)
	select ST_Line_Interpolate_Point(geom, 0.5), segment_id, 'USA'
	from osm.init_streets ins;

--3) Populate street_id via spatial join between this table and streets_conflated
--Do the spatial join
drop index if exists osm.init_stdir_gix cascade;
create index init_stdir_gix on osm.init_stdir using GIST (geom);

drop index if exists osm.streets_conflated_gix cascade;
create index streets_conflated_gix on osm.streets_conflated using GIST (geom);

cluster osm.init_stdir using init_stdir_gix;
vacuum analyze osm.init_stdir;

cluster osm.streets_conflated using streets_conflated_gix;
analyze osm.streets_conflated;

update osm.init_stdir as isd set street_id = sc.id
	from osm.streets_conflated sc
	where ST_Contains(sc.geom, isd.geom);

--4) Populate locality_id via spatial join with prod county, city

--a) create temp tables of the city and county in the project of init street and index them 
drop table if exists city_4326;
create temp table city_4326 as
	select ST_Transform(geom, 4326) as geom, id
	from prod.city;

drop table if exists county_4326;
create temp table county_4326 as
	select ST_Transform(geom, 4326) as geom, id
	from prod.county;

drop index if exists city_4326_gidx cascade;
create index city_4326_gidx on city_4326 using GIST (geom);

drop index if exists county_4326_gidx cascade;
create index county_4326_gidx on county_4326 using GIST (geom);

cluster city_4326 using city_4326_gidx;
vacuum analyze city_4326;

cluster county_4326 using county_4326_gidx;
vacuum analyze county_4326;

--b) give each street mid-point a locality id based on the following hierarchy city, county, region
update osm.init_stdir as isd set locality_id = 
	coalesce('cty' || cty.id, 'co' || co.id, 'metro1')
	from city_4326 cty, county_4326 co
	where ST_Within(isd.geom, cty.geom)
		or ST_Within(isd.geom, co.geom);

drop table city_4326 cascade;
drop table county_4326 cascade;

-- END OF STEP IV:  The street directory file is ready! 