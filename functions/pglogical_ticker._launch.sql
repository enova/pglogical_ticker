CREATE OR REPLACE FUNCTION pglogical_ticker._launch(oid)
 RETURNS integer
 LANGUAGE c
 STRICT
AS '$libdir/pglogical_ticker', $function$pglogical_ticker_launch$function$
;