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
