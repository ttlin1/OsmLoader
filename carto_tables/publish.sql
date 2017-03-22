----------  STREETS ----------

-- display_type key:
--   1 = streets
--   2 = paths
--   3 = bridge
--   4 = rail
--
-- OSM specific display_type values:
--   111 = major arterials (highway=primary,  highway=secondary)
--   131 = arterials       (highway=tertiary)
--   151 = freeways        (highway=motorway, highway=trunk)
--   191 = service roads   (highway=service,  highway=living_street)
--
--    22 = steps
--
--    91 = street construction
--    93 = bridge construction


-- step 0: fix up PostGIS' geometry table and clean up the table
SELECT Populate_Geometry_Columns();
DELETE FROM osmcarto.street;

-- step 1: populate street table from two line tables
INSERT INTO osmcarto.street (osm_id, oneway, highway, label, label_text, geom)
SELECT r.osm_id, r.oneway, r.highway, r.label, r.label_text, r.way
FROM   osmcarto._roads r
WHERE  r.highway != ''
;

INSERT INTO osmcarto.street (osm_id, oneway, highway, label, label_text, geom)
SELECT l.osm_id, l.oneway, l.highway, l.label, l.label_text, l.way
FROM   osmcarto._line l
WHERE  l.highway != ''
AND    l.osm_id NOT IN (SELECT r.osm_id FROM osmcarto._roads r)
;

-- step 2: fix up the one-way label
UPDATE osmcarto.street
SET    direction = '2'
WHERE  oneway = 'yes'
;

UPDATE osmcarto.street
SET    direction = '3'
WHERE  oneway = '-1'
;

-- step 3: fix up data
DELETE FROM osmcarto.street
WHERE highway in ('proposed', 'bridleway')
;

---
-- step 4: separate paths from streets
-- change: FXP Dec 2013 removed 'unclassified'
---
UPDATE osmcarto.street
SET    display_type = '2'
WHERE  highway in ('cycleway', 'footway', 'path', 'pedestrian', 'track')
;

-- step 5: major arterials
--   111 = major arterials (highway=primary,  highway=secondary)
UPDATE osmcarto.street
SET display_type=111
where highway in ('primary', 'secondary', 'primary_link', 'secondary_link')
;

-- step 5b: arterials
--   111 = major arterials (highway=primary,  highway=secondary)
UPDATE osmcarto.street
SET display_type=131
where highway in ('tertiary')
;

-- step 6: highways & freeways
--   151 = freeways        (highway=motorway, highway=trunk)
UPDATE osmcarto.street
SET display_type=151
where highway in ('motorway', 'trunk', 'motorway_link', 'trunk_link')
;

-- step 7: service roads
--   191 = service roads   (highway=service,  highway=living_street)
UPDATE osmcarto.street
SET display_type=191
where highway in ('service', 'living_street', 'raceway')
;

-- step 8: steps & stairs
--    22 = steps
UPDATE osmcarto.street
SET display_type=22
where highway in ('steps')
;

-- step 9: construction
--    91 = street construction
--    93 = bridge construction 
UPDATE osmcarto.street
SET display_type=91
where highway in ('construction')
;
