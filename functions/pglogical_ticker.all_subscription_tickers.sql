CREATE OR REPLACE FUNCTION pglogical_ticker.all_subscription_tickers()
 RETURNS TABLE(provider_name name, set_name name, source_time timestamp with time zone)
 LANGUAGE plpgsql
AS $function$
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
$function$
;