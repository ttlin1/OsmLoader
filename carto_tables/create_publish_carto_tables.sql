--create temp version on trimet_osm_line where construction values are moved
--to the highway field
drop table if exists osm_line_highway_fix cascade;
create temp table osm_line_highway_fix as
	select *,
		case when highway = 'construction'
			and construction is not null then construction
			else highway end as highway_fx,
		case when highway = 'construction'
			and construction is not null then 'yes'
			else construction end as construction_fx
	from osmcarto.trimet_osm_line;

drop table if exists osmcarto.highway cascade;
create table osmcarto.highway (
	--geom and id fields
	geom geometry(Linestring, 3857),
	id int primary key references osmcarto.trimet_osm_line,
	osm_id bigint,
	
	--unaltered osm tags, mostly for reference
	access text,
	bicycle text,
	bridge text,
	bus text,
	construction text,
	cycleway text,
	foot text,
	highway text,
	junction text,
	layer text,
	name text,
	oneway text,
	--osm_name text, --originally 'name', renamed by abbreviation code
	psv text,
	railway text,
	ref text,
	service text,
	surface text,
	tunnel text,
	z_order int,

	--abbreviated label fields
	label bool,
	label_text text,

	--styling fields
	highway_type text,
	subtype text,
	color_group text
);

insert into osmcarto.highway
	--3857 and 900913 are the same, but postgis doesn't realize that so I have to
	--reproject, am going with 3857 because its more widely recogized by gis tools
	select ST_Transform(way, 3857), id, osm_id, access, bicycle, bridge, bus, 
		construction_fx, cycleway, foot, highway_fx, junction, layer, name, oneway, psv, 
		railway, ref, service, surface, tunnel, z_order, null, null,
		--label, label_text,
		--Define the basic type of each feature
		case when highway_fx in ('motorway', 'motorway_link', 'trunk', 'trunk_link',
				'primary', 'primary_link', 'secondary', 'secondary_link', 'tertiary',
				'tertiary_link', 'residential', 'residential_link', 'unclassified', 
				'service', 'living_street', 'track', 'construction', 'road') then 'street'
			when highway_fx in ('footway', 'path', 'cycleway', 'pedestrian', 
				'bridleway', 'track') then 'trail'
			when highway_fx = 'steps' then 'stairs'
			when railway is not null then 'rail'
			else highway_fx end,
		--Define sub groups within larger highway types
		case when highway_fx in ('motorway', 'trunk') then 'freeway'
			when highway_fx in ('primary', 'secondary', 'motorway_link', 
				'trunk_link') then 'arterial'
			when highway_fx in ('tertiary', 'residential', 'unclassified', 'road', 
				'primary_link', 'secondary_link') then 'local'
			when highway_fx in ('service', 'living_street', 'tertiary_link', 
				'residential_link') then 'service'
			when highway_fx = 'cycleway' or (highway_fx = 'path' and foot = 'designated'
				and bicycle = 'designated') then 'multi-use path'
			else null end,
		--In some cases things are grouped together differently
		case when highway_fx in ('motorway', 'motorway_link', 'trunk', 
			'trunk_link') then 'freeway'
			when highway_fx in ('primary', 'primary_link', 'secondary', 
				'secondary_link') then 'arterial'
			when highway_fx in ('tertiary', 'tertiary_link', 'residential',
				'residential_link', 'unclassified', 'road') then 'local'
			when highway_fx in ('service', 'living_street') then 'service'
			else null end
	from osm_line_highway_fix
	where highway is not null
		or railway is not null;

drop table osm_line_highway_fix cascade;