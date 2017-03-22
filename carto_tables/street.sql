DROP TABLE if EXISTS osmcarto.street;
CREATE TABLE osmcarto.street
(
  id SERIAL PRIMARY KEY,
  osm_id INTEGER NOT NULL,
  display_type INTEGER DEFAULT 1,  -- legacy RLIS: 1=street, 2=trail, 3=?, 4=RR
  direction TEXT DEFAULT '0',      -- legacy RLIS: >2=2-way, 2=OneWayForward, 3=OneWayReverse
  oneway    TEXT,                  -- osm one-way: null/no=2-way, yes=OneWayForward, -1=OneWayReverse
  highway   TEXT,                  -- osm highway
  type      TEXT,                  -- used to represent bicycle values (and maybe others) ... 
                                   -- IMPORTANT: it's different than RLIS type, whose values are Rd, St, etc...
  label BOOLEAN DEFAULT TRUE,      -- show a text label on geom
  label_text TEXT                  -- text label for geom
) 
WITH OIDS;
SELECT AddGeometryColumn('osmcarto','street','geom',900913,'LINESTRING','2');

SELECT Populate_Geometry_Columns('osmcarto.street'::regclass);
CREATE INDEX osm_street_ix1 ON osmcarto.street USING btree (label);
CREATE INDEX osm_street_ix2 ON osmcarto.street USING btree (display_type);
CREATE INDEX osm_street_gx  ON osmcarto.street USING gist  (geom);
