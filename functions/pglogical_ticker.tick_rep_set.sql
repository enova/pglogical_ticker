CREATE OR REPLACE FUNCTION pglogical_ticker.tick_rep_set(p_set_name name)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_sql TEXT;
BEGIN

v_sql:=$$
INSERT INTO pglogical_ticker.$$||quote_ident(p_set_name)||$$ (provider_name, source_time)
SELECT ni.if_name, now() AS source_time
FROM pglogical.replication_set rs
INNER JOIN pglogical.node n ON n.node_id = rs.set_nodeid
INNER JOIN pglogical.node_interface ni ON ni.if_nodeid = n.node_id
WHERE EXISTS (SELECT 1
  FROM pglogical_ticker.rep_set_table_wrapper() rsr
  WHERE rsr.set_id = rs.set_id)
ON CONFLICT (provider_name, replication_set_name)
DO UPDATE
SET source_time = now();
$$;

EXECUTE v_sql;

END;
$function$
;
