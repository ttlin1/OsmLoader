-- Copyright 2011, OpenPlans
--
-- Licensed under the GNU Lesser General Public License 3.0 or any
-- later version. See lgpl-3.0.txt for details.

-- Segment OSM ways by intersection to create a routable network

drop table if exists transit_segments cascade;
create table transit_segments (
	id serial primary key,
	node_from_little int,
	node_to_little int,
	way_id bigint references ways,
	node_from_osm bigint references nodes,
	node_to_osm bigint references nodes,
	geom geometry,
	--osm tags are stored in the columns below
	access text,
	aerialway text,
	alt_name text,
	bus text,
	construction text,
	highway text,
	junction text,
	maxspeed text,
	motorway_link text,
	name text, --will become 'osm_name' after street abbreviation module runs
	name_1 text,
	oneway text,
	oneway_bus text,
	oneway_psv text,
	psv text,
	railway text,
	ref text,
	surface text,
	exit_ref text,
	exit_to text
);

-- Intersections are nodes shared by two or more wys
create temporary table intersections(node_id bigint);
insert into intersections 
	select node_id from way_nodes 
	group by node_id having count(way_id) > 1;

-- This table is the same as the way_nodes tables, but adds a column
-- to note whether the node is an intersectoin
create temporary table way_nodes_with_intersection (
	node_id bigint, 
	way_id bigint, 
	sequence_id integer, 
	intersection boolean);

insert into way_nodes_with_intersection 
	select wn.node_id, way_id, sequence_id, i.node_id is not null as intersection 
	from nodes n, way_nodes wn
		left join intersections i on i.node_id = wn.node_id 
	where wn.node_id = n.id;

drop table intersections;

-- First and last nodes of ways are treated as intersections
update way_nodes_with_intersection as o 
	set intersection = true 
	where 
		sequence_id = (select min(x.sequence_id) 
			from way_nodes as x 
			where x.way_id = o.way_id) 
	or 
		sequence_id = (select max(x.sequence_id) 
			from way_nodes as x 
	 		where x.way_id = o.way_id);

-- Fill the street segments table
insert into transit_segments (way_id, node_from_osm, node_to_osm, geom) 
	--This subselect is responsible for getting the geometry
	select g.way_id, node_from, node_to, st_makeline(geom order by g.sequence_id)
	from way_nodes_with_intersection as g, nodes, 
	-- and this one gets a from and to node id and sequence number where
	-- from and to are intersections and no nodes between from and to are
	-- intersections
		(select f.way_id, f.node_id as node_from, t.node_id as node_to, f.sequence_id as f_seq, t.sequence_id as t_seq
		from way_nodes_with_intersection as f, way_nodes_with_intersection as t
		where t.way_id = f.way_id 
			and f.intersection = true
			and t.intersection = true
			and f.sequence_id < t.sequence_id
			--make sure there are no other intersection nodes between the
			--the two intersections that are being joined
			and not exists (select between_wn.node_id as x
							from way_nodes_with_intersection as between_wn
							where between_wn.way_id = f.way_id
								and between_wn.intersection = true
								and between_wn.sequence_id > f.sequence_id
								and between_wn.sequence_id < t.sequence_id)) as rest_q
	where nodes.id = g.node_id
		and g.way_id = rest_q.way_id
		and g.sequence_id >= f_seq
		and g.sequence_id <= t_seq
	group by g.way_id, node_from, node_to;

drop table way_nodes_with_intersection;

--Index will be used in bounding box comparison in populating init and hastus tables
drop index if exists osm.transit_segments_gix cascade;
create index transit_segments_gix on osm.transit_segments using GIST (geom);

--These indices will be utilized when creating hastus turns
drop index if exists osm.trans_segs_node_from_osm_ix cascade;
create index trans_segs_node_from_osm_ix on osm.transit_segments using BTREE (node_from_osm);

drop index if exists osm.trans_segs_node_to_osm_ix cascade;
create index trans_segs_node_to_osm_ix on osm.transit_segments using BTREE (node_to_osm);

--Clean up after insertions and addition of indices (will improve performance)
vacuum analyze osm.transit_segments;


--These indices will speed the updates below, way_tags.way_id already has an index as a result
--of the script run to create the osmosis schema
drop index if exists osm.trans_segs_way_id_ix cascade;
create index trans_segs_way_id_ix on osm.transit_segments using BTREE (way_id);

drop index if exists osm.way_tags_k_ix cascade;
create index way_tags_k_ix on osm.way_tags using BTREE (k);

drop index if exists osm.node_tags_k_ix cascade;
create index node_tags_k_ix on osm.node_tags using BTREE (k);

drop index if exists osm.node_tags_v_ix cascade;
create index node_tags_v_ix on osm.node_tags using BTREE (v);

-- Fill in the fields for all tags that will be needed to populate the init and hastus attributes
update transit_segments as ts set
	access = (select v from way_tags wt
		where wt.way_id = ts.way_id and k = 'access'),

	aerialway = (select v from way_tags wt
		where wt.way_id = ts.way_id and k = 'aerialway'),

	alt_name = (select v from way_tags wt
		where wt.way_id = ts.way_id and k = 'alt_name'),

	bus = (select v from way_tags wt
		where wt.way_id = ts.way_id and k = 'bus'),

	construction = (select v from way_tags wt
		where wt.way_id = ts.way_id and k = 'construction'),

	highway = (select v from way_tags wt
		where wt.way_id = ts.way_id and k = 'highway'),

	junction = (select v from way_tags wt
		where wt.way_id = ts.way_id and k = 'junction'),

	maxspeed = (select v from way_tags wt
		where wt.way_id = ts.way_id and k = 'maxspeed'),

	motorway_link = (select v from way_tags wt
		where wt.way_id = ts.way_id and k = 'motorway_link'),

	name = (select v from way_tags wt
		where wt.way_id = ts.way_id and k = 'name'),

	name_1 = (select v from way_tags wt
		where wt.way_id = ts.way_id and k = 'name_1'),

	oneway = (select v from way_tags wt
		where wt.way_id = ts.way_id and k = 'oneway'),

	oneway_bus = (select v from way_tags wt
		where wt.way_id = ts.way_id and k = 'oneway:bus'),

	oneway_psv = (select v from way_tags wt
		where wt.way_id = ts.way_id and k = 'oneway:psv'),

	psv = (select v from way_tags wt
		where wt.way_id = ts.way_id and k = 'psv'),

	railway = (select v from way_tags wt
		where wt.way_id = ts.way_id and k = 'railway'),

	ref = (select v from way_tags wt
		where wt.way_id = ts.way_id and k = 'ref'),

	surface = (select v from way_tags wt
		where wt.way_id = ts.way_id and k = 'surface'),

	--derive information from freeway exit nodes and apply it to the freeway ramps that they
	--belong to
	exit_ref = (select nt.v from osm.node_tags nt, osm.nodes n
		where ts.node_from_osm = n.id
			and n.id = nt.node_id
			and nt.k = 'ref'
			and exists (select null from osm.node_tags nt2 
						where ts.node_from_osm = nt2.node_id 
							and nt2.k = 'highway' 
							and nt2.v = 'motorway_junction')),

	exit_to = (select nt.v from osm.node_tags nt, osm.nodes n
		where ts.node_from_osm = n.id
			and n.id = nt.node_id
			and nt.k = 'exit_to'
			and exists (select null from osm.node_tags nt2 
						where ts.node_from_osm = nt2.node_id 
							and nt2.k = 'highway' 
							and nt2.v = 'motorway_junction'));

--Now add indices to these columns as they will be used for matching in the population
--of the init/hastus tables, but won't be modified from this point
drop index if exists osm.trans_segs_access_ix cascade;
create index trans_segs_access_ix on osm.transit_segments using BTREE (access);

drop index if exists osm.trans_segs_aerialway_ix cascade;
create index trans_segs_aerialway_ix on osm.transit_segments using BTREE (aerialway);

drop index if exists osm.trans_segs_alt_name_ix cascade;
create index trans_segs_alt_name_ix on osm.transit_segments using BTREE (alt_name);

drop index if exists osm.trans_segs_bus_ix cascade;
create index trans_segs_bus_ix on osm.transit_segments using BTREE (bus);

drop index if exists osm.trans_segs_construction_ix cascade;
create index trans_segs_construction_ix on osm.transit_segments using BTREE (construction);

drop index if exists osm.trans_segs_highway_ix cascade;
create index trans_segs_highway_ix on osm.transit_segments using BTREE (highway);

drop index if exists osm.trans_segs_junction_ix cascade;
create index trans_segs_junction_ix on osm.transit_segments using BTREE (junction);

drop index if exists osm.trans_segs_maxspeed_ix cascade;
create index trans_segs_maxspeed_ix on osm.transit_segments using BTREE (maxspeed);

drop index if exists osm.trans_segs_name_1_ix cascade;
create index trans_segs_name_1_ix on osm.transit_segments using BTREE (name_1);

drop index if exists osm.trans_segs_oneway_ix cascade;
create index trans_segs_oneway_ix on osm.transit_segments using BTREE (oneway);

drop index if exists osm.trans_segs_oneway_bus_ix cascade;
create index trans_segs_oneway_bus_ix on osm.transit_segments using BTREE (oneway_bus);

drop index if exists osm.trans_segs_oneway_psv_ix cascade;
create index trans_segs_oneway_psv_ix on osm.transit_segments using BTREE (oneway_psv);

drop index if exists osm.trans_segs_psv_ix cascade;
create index trans_segs_psv_ix on osm.transit_segments using BTREE (psv);

drop index if exists osm.trans_segs_railway_ix cascade;
create index trans_segs_railway_ix on osm.transit_segments using BTREE (railway);

drop index if exists osm.trans_segs_ref_ix cascade;
create index trans_segs_ref_ix on osm.transit_segments using BTREE (ref);

drop index if exists osm.trans_segs_surface_ix cascade;
create index trans_segs_surface_ix on osm.transit_segments using BTREE (surface);

drop index if exists osm.trans_segs_exit_ref_ix cascade;
create index trans_segs_exit_ref_ix on osm.transit_segments using BTREE (exit_ref);

drop index if exists osm.trans_segs_exit_to_ix cascade;
create index trans_segs_exit_to_ix on osm.transit_segments using BTREE (exit_to);

--Clean up after insertions and addition of indices (will improve performance)
vacuum analyze osm.transit_segments;


--Map node IDs (which have exceeded 32-bit integer space in OSM) to a new attribute
--to condense them so that they don't require bigint (which Init & Hastus can't handle)

--create new sequential id on nodes in or-wa osm export
alter table osm.nodes drop column if exists little_id cascade;
alter table osm.nodes add little_id serial unique;

update osm.transit_segments ts set
	node_from_little = (select little_id from osm.nodes n
		where ts.node_from_osm = n.id),

	node_to_little = (select little_id from osm.nodes n
		where ts.node_to_osm = n.id);


--Delete any duplicate segments, if they exist, and store their way id's in a table so that
--they can be used to correct osm data

--Create a table that contains the way id's 
drop table if exists osm.duplicate_segments cascade;
create table osm.duplicate_segments with oids as
	select distinct ts1.way_id as osm_way_id1, ts2.way_id as osm_way_id2
	from osm.transit_segments ts1, osm.transit_segments ts2
	--this both elimnates a segment from matching itself and ensures that unique pairs appear
	--only once (so for instance you get only (2,1) instead of both (2,1) and (1,2) as entries)
	where ts1.id > ts2.id
		and ST_Equals(ts1.geom, ts2.geom)
	order by osm_way_id1;

create or replace function delete_duplicates_if_exists() returns void as $$
begin
	--if the duplicates table is empty drop it and move on with the script
	if (select count(*) from osm.duplicate_segments) = 0 then
		drop table osm.duplicate_segments cascade;
	else
		--if duplicates segments exist delete one of them
		delete from osm.transit_segments 
			--amongst each pair of duplicates delete the one that belongs to the osm way that has
			--fewer nodes (I've found the smaller osm ways to be the erroneous ones in most cases) 
			where id in (select case when (select count(*) from osm.way_nodes where way_id = ts1.way_id) >
							(select count(*) from osm.way_nodes where way_id = ts2.way_id) then ts1.id
							else ts2.id end
						from osm.transit_segments ts1, osm.transit_segments ts2
						where ts1.id > ts2.id
							and ST_Equals(ts1.geom, ts2.geom));
		--write to the log that duplicates exist and need to be corrected in osm
		raise notice '******************************************************';
		raise notice 'Duplicate features exist in or-wa.osm and have been removed from osm.transit_segments';
		raise notice 'The id''s of the osm ways that the duplicate segments belong to are stored in osm.duplicate_segments';
		raise notice 'Correct these errors in osm to improve data and ensure the proper copy is being retained.';
		raise notice '******************************************************';
	end if;
end;
$$ language plpgsql;

select delete_duplicates_if_exists();


-- create a table to hold joined streets
drop table if exists streets_conflated cascade;
create table streets_conflated (
	id serial primary key,
	name text,
	osm_name text,
	alt_name text,
	highway text not null,
	oneway text,
	length float not null,
	geom geometry);


-- load turn restrictions
drop table if exists turn_restrictions cascade;
create table turn_restrictions (
	osm_restriction_id bigint not null references relations,
	segment_from integer not null references transit_segments,
	segment_to integer not null references transit_segments,
	node bigint not null references nodes,
	type text,
	exceptions text);

insert into turn_restrictions 
	select tags.relation_id, seg1.id, seg2.id, via.member_id, tags.v, tags2.v
	from relation_tags as tags, 
		relation_members as via
			left outer join relation_tags as tags2
			on tags2.relation_id = via.relation_id
				and tags2.k = 'except',
		relation_members as from_relation, relation_members as to_relation, 
		transit_segments as seg1, transit_segments as seg2
	where ((tags2.v is null) or (not (tags2.v like '%psv%' or tags2.v like '%bus%')))
		and tags.k = 'restriction'
		and tags.relation_id = via.relation_id
		and via.relation_id = from_relation.relation_id
		and from_relation.relation_id = to_relation.relation_id
		and via.member_role='via' 
		and via.member_type='N'
		and from_relation.member_role = 'from'
		and from_relation.member_type='W'
		and to_relation.member_role = 'to'
		and to_relation.member_type='W'
		and seg1.way_id = from_relation.member_id
		and seg2.way_id = to_relation.member_id
		and (seg1.node_from_osm = via.member_id or seg1.node_to_osm = via.member_id)
		and (seg2.node_from_osm = via.member_id or seg2.node_to_osm = via.member_id);


drop table if exists turns_prohibited cascade;
create table turns_prohibited (
	osm_restriction_id bigint not null references relations,
	segment_from integer not null references transit_segments,
	segment_to integer not null references transit_segments,
	node_osm bigint not null references nodes,
	node_little int,
	exceptions text);

insert into turns_prohibited (osm_restriction_id, segment_from, segment_to, node_osm, exceptions)
	select tags.relation_id, seg1.id, seg2.id, via.member_id, tags2.v
	from relation_tags as tags, 
		relation_members as via
			left outer join relation_tags as tags2 
			on tags2.relation_id = via.relation_id 
				and tags2.k = 'except',
		relation_members as from_relation, 
		relation_members as to_relation, 
		transit_segments as seg1,
		transit_segments as seg2
	where ((tags2.v is null) or (not (tags2.v like '%psv%' or tags2.v like '%bus%')))
		and tags.k = 'restriction'
		and tags.relation_id = via.relation_id
		and via.relation_id = from_relation.relation_id
		and from_relation.relation_id = to_relation.relation_id
		and via.member_role='via' and via.member_type='N'
		and from_relation.member_role = 'from' and from_relation.member_type='W'
		and to_relation.member_role = 'to'
		and to_relation.member_type='W'
		and (((tags.v = 'no_u_turn' or tags.v = 'no_straight_on' or tags.v = 'no_left_turn' or tags.v = 'no_right_turn')
				and seg1.way_id = from_relation.member_id
				and seg2.way_id = to_relation.member_id)
			or ((tags.v = 'only_straight_on' or tags.v = 'only_left_turn' or tags.v = 'only_right_turn')
				and seg1.way_id = from_relation.member_id
				and seg2.way_id <> to_relation.member_id))
		and (seg1.node_from_osm = via.member_id or seg1.node_to_osm = via.member_id)
		and (seg2.node_from_osm = via.member_id or seg2.node_to_osm = via.member_id)
		and seg1.id != seg2.id;

--These two will be used in the Hastus conversion
drop index if exists osm.turns_prohibited_f_seg_ix cascade;
create index turns_prohibited_f_seg_ix on osm.turns_prohibited using BTREE (segment_from);

drop index if exists osm.turns_prohibited_t_seg_ix cascade;
create index turns_prohibited_t_seg_ix on osm.turns_prohibited using BTREE (segment_to);

--Bring in remapped node id's so that init and hastus can consume this information
drop index if exists osm.turns_prohibited_node_osm_ix cascade;
create index turns_prohibited_node_osm_ix on osm.turns_prohibited using BTREE (node_osm);

update osm.turns_prohibited tp set
	node_little = (select little_id from osm.nodes n
		where tp.node_osm = n.id);

--and this one is used in the Init conversion
drop index if exists osm.turns_prohibited_node_little_ix cascade;
create index turns_prohibited_node_little_ix on osm.turns_prohibited using BTREE (node_little);