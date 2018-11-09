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
