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
