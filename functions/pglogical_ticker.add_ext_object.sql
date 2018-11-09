CREATE OR REPLACE FUNCTION pglogical_ticker.add_ext_object(p_type text, p_full_obj_name text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
PERFORM pglogical_ticker.toggle_ext_object(p_type, p_full_obj_name, 'ADD');
END;
$function$
;