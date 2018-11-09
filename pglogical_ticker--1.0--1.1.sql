/* pglogical_ticker--1.0--1.1.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pglogical_ticker" to load this file. \quit

--This must be done AFTER we update the function def
SELECT pglogical_ticker.drop_ext_object('FUNCTION','pglogical_ticker.dependency_update()');
DROP FUNCTION pglogical_ticker.dependency_update();
SELECT pglogical_ticker.drop_ext_object('VIEW','pglogical_ticker.rep_set_table_wrapper');
DROP VIEW IF EXISTS pglogical_ticker.rep_set_table_wrapper; 


CREATE OR REPLACE FUNCTION pglogical_ticker.toggle_ext_object(p_type text, p_full_obj_name text, p_toggle text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  c_valid_types TEXT[] = ARRAY['EVENT TRIGGER','FUNCTION','VIEW','TABLE'];
  c_valid_toggles TEXT[] = ARRAY['ADD','DROP'];
BEGIN

IF NOT (SELECT ARRAY[upper(p_type)] && c_valid_types) THEN
  RAISE EXCEPTION 'Must pass one of % as 1st arg.', array_to_string(c_valid_types,',');
END IF;

IF NOT (SELECT ARRAY[upper(p_toggle)] && c_valid_toggles) THEN
  RAISE EXCEPTION 'Must pass one of % as 3rd arg.', array_to_string(c_valid_toggles,',');
END IF;

EXECUTE 'ALTER EXTENSION pglogical_ticker '||p_toggle||' '||p_type||' '||p_full_obj_name;

EXCEPTION
  WHEN undefined_function THEN
    RETURN;
  WHEN undefined_object THEN
    RETURN;
  WHEN object_not_in_prerequisite_state THEN
    RETURN;

END;
$function$
;


CREATE OR REPLACE FUNCTION pglogical_ticker.rep_set_table_wrapper()
 RETURNS TABLE (set_id OID, set_reloid REGCLASS)
 LANGUAGE plpgsql
AS $function$
/*****
This handles the rename of pglogical.replication_set_relation to pglogical_ticker.rep_set_table_wrapper from version 1 to 2
 */
BEGIN

IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'pglogical' AND tablename = 'replication_set_table') THEN
    RETURN QUERY
    SELECT r.set_id, r.set_reloid 
    FROM pglogical.replication_set_table r;

ELSEIF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'pglogical' AND tablename = 'replication_set_relation') THEN
    RETURN QUERY
    SELECT r.set_id, r.set_reloid 
    FROM pglogical.replication_set_relation r;

ELSE
    RAISE EXCEPTION 'No table pglogical.replication_set_relation or pglogical.replication_set_table found';
END IF;

END;
$function$
;


CREATE OR REPLACE FUNCTION pglogical_ticker.add_ticker_tables_to_replication()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE v_row_count INT;
BEGIN
/****
This will add all ticker tables
to replication if not done already.

It assumes of course pglogical_ticker.deploy_ticker_tables()
has been run.
 */
PERFORM rs.set_name, pglogical.replication_set_add_table(
  set_name:=rs.set_name
  ,relation:=('pglogical_ticker.'||quote_ident(set_name))::REGCLASS
  --default synchronize_data is false
  ,synchronize_data:=false
)
FROM pglogical.replication_set rs 
WHERE NOT EXISTS
  (SELECT 1
  FROM pglogical_ticker.rep_set_table_wrapper() rsr
  WHERE rsr.set_reloid = ('pglogical_ticker.'||quote_ident(set_name))::REGCLASS 
    AND rsr.set_id = rs.set_id);

GET DIAGNOSTICS v_row_count = ROW_COUNT;
RETURN v_row_count;

END;
$function$
;


CREATE OR REPLACE FUNCTION pglogical_ticker.tick_rep_set(p_set_name name)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_sql TEXT;
BEGIN

v_sql:=$$
INSERT INTO pglogical_ticker.$$||quote_ident(p_set_name)||$$ (provider_name, source_time)
SELECT ni.if_name, now() AS source_time
FROM pglogical.replication_set rs
INNER JOIN pglogical.node n ON n.node_id = rs.set_nodeid
INNER JOIN pglogical.node_interface ni ON ni.if_nodeid = n.node_id
WHERE EXISTS (SELECT 1
  FROM pglogical_ticker.rep_set_table_wrapper() rsr
  WHERE rsr.set_id = rs.set_id)
ON CONFLICT (provider_name, replication_set_name)
DO UPDATE
SET source_time = now();
$$;

EXECUTE v_sql;

END;
$function$
;


CREATE OR REPLACE FUNCTION pglogical_ticker.launch()
 RETURNS integer
 LANGUAGE sql
 STRICT
AS $function$
SELECT pglogical_ticker._launch(oid)
FROM pg_database
WHERE datname = current_database()
--This should be improved in the future but should do 
--the job for now.
AND NOT EXISTS
    (SELECT 1
    FROM pg_stat_activity psa
    WHERE NOT pid = pg_backend_pid()
      AND query = 'SELECT pglogical_ticker.tick();')
AND NOT pg_is_in_recovery();
$function$
;

CREATE OR REPLACE FUNCTION pglogical_ticker.launch_if_repset_tables()
 RETURNS integer
 LANGUAGE sql
AS $function$
SELECT pglogical_ticker.launch()
WHERE EXISTS (SELECT 1 FROM pglogical_ticker.rep_set_table_wrapper());
$function$
;

