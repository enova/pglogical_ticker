/* pglogical_ticker--1.3--1.4.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pglogical_ticker" to load this file. \quit

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
      AND application_name LIKE 'pglogical_ticker%')
AND NOT pg_is_in_recovery();
$function$
;


