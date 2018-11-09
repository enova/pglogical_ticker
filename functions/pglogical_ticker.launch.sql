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