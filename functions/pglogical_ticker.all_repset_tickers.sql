CREATE OR REPLACE FUNCTION pglogical_ticker.all_repset_tickers()
 RETURNS TABLE(provider_name name, set_name name, source_time timestamp with time zone)
 LANGUAGE plpgsql
AS $function$
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
$function$
;