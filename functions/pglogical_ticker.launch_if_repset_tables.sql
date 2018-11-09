CREATE OR REPLACE FUNCTION pglogical_ticker.launch_if_repset_tables()
 RETURNS integer
 LANGUAGE sql
AS $function$
SELECT pglogical_ticker.launch()
WHERE EXISTS (SELECT 1 FROM pglogical_ticker.rep_set_table_wrapper());
$function$
;