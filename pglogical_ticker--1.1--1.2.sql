/* pglogical_ticker--1.1--1.2.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pglogical_ticker" to load this file. \quit

DROP FUNCTION pglogical_ticker.deploy_ticker_tables(); 
DROP FUNCTION pglogical_ticker.add_ticker_tables_to_replication();
CREATE OR REPLACE FUNCTION pglogical_ticker.eligible_tickers
(
/***
"Eligible tickers" are defined as replication sets and tables
that are eligible to be created or added to replication, either
because the replication sets exist, or with cascading replication,
the tables already exist to add to a specified replication set 
p_cascade_to_set_name as cascaded tickers.
***/
p_cascade_to_set_name NAME = NULL 
)
 RETURNS TABLE (set_name name, tablename name) 
 LANGUAGE plpgsql
AS $function$
/****
It assumes this extension is installed both places!
 */
BEGIN

RETURN QUERY
--In the generic case, always tablename = set_name 
SELECT rs.set_name, rs.set_name AS tablename
FROM pglogical.replication_set rs
WHERE p_cascade_to_set_name IS NULL
UNION
--For cascading replication, we override set_name
SELECT p_cascade_to_set_name AS set_name_out, relname AS tablename
FROM pg_class c
INNER JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE p_cascade_to_set_name IS NOT NULL 
AND n.nspname = 'pglogical_ticker'
AND c.relkind = 'r'
AND EXISTS (
    SELECT 1
    FROM pglogical.replication_set rsi
    WHERE rsi.set_name = p_cascade_to_set_name
);

END;
$function$
;


CREATE OR REPLACE FUNCTION pglogical_ticker.deploy_ticker_tables(
--For use with cascading replication, you can pass
--a set_name in order to add all current subscription tickers 
--to this replication set
p_cascade_to_set_name NAME = NULL 
)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
/****
This will create the main table on both provider and
all subscriber(s) for in use replication sets.

It assumes this extension is installed both places.
 */
DECLARE
    v_row_count INT;
BEGIN

PERFORM pglogical.replicate_ddl_command($$
CREATE TABLE IF NOT EXISTS pglogical_ticker.$$||quote_ident(tablename)||$$ (
  provider_name        NAME PRIMARY KEY,
  source_time          TIMESTAMPTZ
);

SELECT pglogical_ticker.add_ext_object(
'TABLE',
format('%s.%s',
      'pglogical_ticker',
      quote_ident($$||quote_literal(tablename)||$$)
      )
);
$$, ARRAY[set_name])
FROM pglogical_ticker.eligible_tickers(p_cascade_to_set_name);

GET DIAGNOSTICS v_row_count = ROW_COUNT;
RETURN v_row_count;

END;
$function$
;


CREATE OR REPLACE FUNCTION pglogical_ticker.add_ticker_tables_to_replication(
--For use with cascading replication, you can pass
--a set_name in order to add all current subscription tickers
--to this replication set
p_cascade_to_set_name NAME = NULL
)
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
PERFORM et.set_name, pglogical.replication_set_add_table(
  set_name:=et.set_name
  ,relation:=('pglogical_ticker.'||quote_ident(et.tablename))::REGCLASS
  --default synchronize_data is false
  ,synchronize_data:=false
)
FROM pglogical_ticker.eligible_tickers(p_cascade_to_set_name) et
WHERE NOT EXISTS
  (SELECT 1
  FROM pglogical_ticker.rep_set_table_wrapper() rsr
  INNER JOIN pglogical.replication_set rs ON rs.set_id = rsr.set_id
  WHERE rsr.set_reloid = ('pglogical_ticker.'||quote_ident(et.tablename))::REGCLASS 
    AND et.set_name = rs.set_name);

GET DIAGNOSTICS v_row_count = ROW_COUNT;
RETURN v_row_count;

END;
$function$
;


CREATE OR REPLACE FUNCTION pglogical_ticker.tick()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE 
    v_record RECORD;
    v_sql TEXT;
    v_row_count INT;
BEGIN

FOR v_record IN
    SELECT rs.set_name
    FROM pglogical.replication_set rs
    /***
    Don't try to tick tables that don't yet exist.  This will allow
    us to create replication sets without worrying about adding a ticker table
    immediately.
    ***/
    WHERE EXISTS
        (SELECT 1
        FROM pg_class c
        INNER JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'pglogical_ticker'
          AND c.relname = rs.set_name
          /***
          Also avoid uselessly ticking tables that are not in any replication set
          (regardless of which one)
          ***/
          AND EXISTS
            (SELECT 1
            FROM pglogical_ticker.rep_set_table_wrapper() rst
            WHERE c.oid = rst.set_reloid) 
        )
    ORDER BY rs.set_name
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
$function$
;


