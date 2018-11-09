CREATE OR REPLACE FUNCTION pglogical_ticker.tick()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE 
    v_record RECORD;
    v_sql TEXT;
    v_row_count INT;
BEGIN

FOR v_record IN
    SELECT rs.set_name
    FROM pglogical.replication_set rs
    /***
    Don't try to tick tables that don't yet exist.  This will allow
    us to create replication sets without worrying about adding a ticker table
    immediately.
    ***/
    WHERE EXISTS
        (SELECT 1
        FROM pg_class c
        INNER JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'pglogical_ticker'
          AND c.relname = rs.set_name
          /***
          Also avoid uselessly ticking tables that are not in any replication set
          (regardless of which one)
          ***/
          AND EXISTS
            (SELECT 1
            FROM pglogical_ticker.rep_set_table_wrapper() rst
            WHERE c.oid = rst.set_reloid) 
        )
    ORDER BY rs.set_name
LOOP

    v_sql:=$$
    INSERT INTO pglogical_ticker.$$||quote_ident(v_record.set_name)||$$ (provider_name, source_time)
    SELECT ni.if_name, now() AS source_time
    FROM pglogical.replication_set rs
    INNER JOIN pglogical.node n ON n.node_id = rs.set_nodeid
    INNER JOIN pglogical.node_interface ni ON ni.if_nodeid = n.node_id
    WHERE rs.set_name = '$$||quote_ident(v_record.set_name)||$$'
    ON CONFLICT (provider_name)
    DO UPDATE
    SET source_time = now();
    $$;

    EXECUTE v_sql;

END LOOP;

END;
$function$
;
