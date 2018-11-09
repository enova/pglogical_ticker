/* pglogical_ticker--1.0.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pglogical_ticker" to load this file. \quit

CREATE FUNCTION pglogical_ticker._launch(oid)
  RETURNS pg_catalog.INT4 STRICT
AS 'MODULE_PATHNAME', 'pglogical_ticker_launch'
LANGUAGE C;

CREATE FUNCTION pglogical_ticker.launch()
  RETURNS pg_catalog.INT4 STRICT
AS $BODY$
SELECT pglogical_ticker._launch(oid)
FROM pg_database
WHERE datname = current_database()
--This should be improved in the future but should do 
--the job for now.
AND NOT EXISTS
    (SELECT 1
    FROM pg_stat_activity psa
    WHERE NOT pid = pg_backend_pid()
      AND query = 'SELECT pglogical_ticker.tick();');
$BODY$
LANGUAGE SQL;

CREATE FUNCTION pglogical_ticker.dependency_update()
RETURNS VOID AS
$DEPS$
/*****
This handles the rename of pglogical.replication_set_relation to pglogical_ticker.rep_set_table_wrapper from version 1 to 2
 */
BEGIN

IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'rep_set_table_wrapper' AND table_schema = 'pglogical_ticker') THEN
    PERFORM pglogical_ticker.drop_ext_object('VIEW','pglogical_ticker.rep_set_table_wrapper');
    DROP VIEW pglogical_ticker.rep_set_table_wrapper;
END IF;
IF (SELECT extversion FROM pg_extension WHERE extname = 'pglogical') ~* '^1.*' THEN

    CREATE VIEW pglogical_ticker.rep_set_table_wrapper AS
    SELECT *
    FROM pglogical.replication_set_relation;

ELSE

    CREATE VIEW pglogical_ticker.rep_set_table_wrapper AS
    SELECT *
    FROM pglogical.replication_set_table;

END IF;

END;
$DEPS$
LANGUAGE plpgsql;

SELECT pglogical_ticker.dependency_update();

CREATE OR REPLACE FUNCTION pglogical_ticker.add_ext_object
  (p_type text
  , p_full_obj_name text)
RETURNS VOID AS
$BODY$
BEGIN
PERFORM pglogical_ticker.toggle_ext_object(p_type, p_full_obj_name, 'ADD');
END;
$BODY$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pglogical_ticker.drop_ext_object
  (p_type text
  , p_full_obj_name text)
RETURNS VOID AS
$BODY$
BEGIN
PERFORM pglogical_ticker.toggle_ext_object(p_type, p_full_obj_name, 'DROP');
END;
$BODY$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pglogical_ticker.toggle_ext_object
  (p_type text
  , p_full_obj_name text
  , p_toggle text)
RETURNS VOID AS
$BODY$
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

/*EXCEPTION
  WHEN undefined_function THEN
    RETURN;
  WHEN undefined_object THEN
    RETURN;
  WHEN object_not_in_prerequisite_state THEN
    RETURN;
*/
END;
$BODY$
LANGUAGE plpgsql;

CREATE FUNCTION pglogical_ticker.deploy_ticker_tables()
RETURNS INT AS
$BODY$
/****
This will create the main table on both provider and
all subscriber(s) for in use replication sets.

It assumes this extension is installed both places.
 */
DECLARE
    v_row_count INT;
BEGIN

PERFORM pglogical.replicate_ddl_command($$
CREATE TABLE IF NOT EXISTS pglogical_ticker.$$||quote_ident(set_name)||$$ (
  provider_name        NAME PRIMARY KEY,
  source_time          TIMESTAMPTZ
);$$, ARRAY[set_name])
FROM pglogical.replication_set;

PERFORM pglogical_ticker.add_ext_object('TABLE', 'pglogical_ticker.'||quote_ident(set_name))
FROM pglogical.replication_set;

GET DIAGNOSTICS v_row_count = ROW_COUNT;
RETURN v_row_count;

END;
$BODY$
LANGUAGE plpgsql;

CREATE FUNCTION pglogical_ticker.all_repset_tickers()
RETURNS TABLE (provider_name NAME, set_name NAME, source_time TIMESTAMPTZ)
AS
$BODY$
DECLARE v_sql TEXT;
BEGIN

SELECT COALESCE(
        string_agg(
            format(
                'SELECT provider_name, %s::NAME AS set_name, source_time FROM %s',
                quote_literal(rs.set_name),
                relid::REGCLASS::TEXT
                ),
            E'\nUNION ALL\n'
            ),
        'SELECT NULL::NAME, NULL::NAME, NULL::TIMESTAMPTZ') INTO v_sql
FROM pg_stat_user_tables st
INNER JOIN pglogical.replication_set rs ON rs.set_name = st.relname
WHERE schemaname = 'pglogical_ticker'; 

RETURN QUERY EXECUTE v_sql;

END;
$BODY$
LANGUAGE plpgsql;

CREATE FUNCTION pglogical_ticker.all_subscription_tickers()
RETURNS TABLE (provider_name NAME, set_name NAME, source_time TIMESTAMPTZ)
AS
$BODY$
DECLARE v_sql TEXT;
BEGIN

WITH sub_rep_sets AS (
SELECT DISTINCT unnest(sub_replication_sets) AS set_name
FROM pglogical.subscription
)

SELECT COALESCE(
        string_agg(
            format(
                'SELECT provider_name, %s::NAME AS set_name, source_time FROM %s',
                quote_literal(srs.set_name),
                relid::REGCLASS::TEXT
                ),
            E'\nUNION ALL\n'
            ),
        'SELECT NULL::NAME, NULL::NAME, NULL::TIMESTAMPTZ') INTO v_sql
FROM pg_stat_user_tables st
INNER JOIN sub_rep_sets srs ON srs.set_name = st.relname
WHERE schemaname = 'pglogical_ticker'; 

RETURN QUERY EXECUTE v_sql;

END;
$BODY$
LANGUAGE plpgsql;

CREATE FUNCTION pglogical_ticker.add_ticker_tables_to_replication()
RETURNS INT AS
$BODY$
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
  FROM pglogical_ticker.rep_set_table_wrapper rsr
  WHERE rsr.set_reloid = ('pglogical_ticker.'||quote_ident(set_name))::REGCLASS 
    AND rsr.set_id = rs.set_id);

GET DIAGNOSTICS v_row_count = ROW_COUNT;
RETURN v_row_count;

END;
$BODY$
LANGUAGE plpgsql;

CREATE FUNCTION pglogical_ticker.tick_rep_set(p_set_name name)
RETURNS INT AS
$BODY$
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
  FROM pglogical_ticker.rep_set_table_wrapper rsr
  WHERE rsr.set_id = rs.set_id)
ON CONFLICT (provider_name, replication_set_name)
DO UPDATE
SET source_time = now();
$$;

EXECUTE v_sql;

END;
$BODY$
LANGUAGE plpgsql;

CREATE FUNCTION pglogical_ticker.tick()
RETURNS VOID AS
$BODY$
DECLARE 
    v_record RECORD;
    v_sql TEXT;
    v_row_count INT;
BEGIN

FOR v_record IN SELECT set_name FROM pglogical.replication_set ORDER BY set_name
LOOP

    v_sql:=$$
    INSERT INTO pglogical_ticker.$$||quote_ident(v_record.set_name)||$$ (provider_name, source_time)
    SELECT ni.if_name, now() AS source_time
    FROM pglogical.replication_set rs
    INNER JOIN pglogical.node n ON n.node_id = rs.set_nodeid
    INNER JOIN pglogical.node_interface ni ON ni.if_nodeid = n.node_id
    WHERE rs.set_name = '$$||quote_ident(v_record.set_name)||$$'
    ON CONFLICT (provider_name)
    DO UPDATE
    SET source_time = now();
    $$;

    EXECUTE v_sql;

END LOOP;

END;
$BODY$
LANGUAGE plpgsql;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA pglogical_ticker FROM PUBLIC;
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

