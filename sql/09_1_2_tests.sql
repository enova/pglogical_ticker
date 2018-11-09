SET client_min_messages TO warning;
WITH sets AS (
SELECT 'test'||generate_series AS set_name
FROM generate_series(11,12)
)

SELECT pglogical.create_replication_set
(set_name:=s.set_name
,replicate_insert:=TRUE
,replicate_update:=TRUE
,replicate_delete:=TRUE
,replicate_truncate:=TRUE) AS result
INTO TEMP repsets
FROM sets s
WHERE NOT EXISTS (
SELECT 1
FROM pglogical.replication_set
WHERE set_name = s.set_name);

DROP TABLE repsets;

/*** PRIOR TO 1.2, THIS WOULD SHOW THE FOLLOWING ERROR

ERROR:  relation "pglogical_ticker.test11" does not exist
LINE 2:     INSERT INTO pglogical_ticker.test11 (provider_name, sour...
                        ^
QUERY:
    INSERT INTO pglogical_ticker.test11 (provider_name, source_time)
    SELECT ni.if_name, now() AS source_time
    FROM pglogical.replication_set rs
    INNER JOIN pglogical.node n ON n.node_id = rs.set_nodeid
    INNER JOIN pglogical.node_interface ni ON ni.if_nodeid = n.node_id
    WHERE rs.set_name = 'test11'
    ON CONFLICT (provider_name)
    DO UPDATE
    SET source_time = now();

CONTEXT:  PL/pgSQL function pglogical_ticker.tick() line 23 at EXECUTE

***/

SELECT pglogical_ticker.tick();

SELECT * FROM pglogical_ticker.eligible_tickers() ORDER BY set_name, tablename;
SELECT * FROM pglogical_ticker.eligible_tickers('test1') ORDER BY set_name, tablename;

SELECT pglogical_ticker.deploy_ticker_tables('test1');
SELECT pglogical_ticker.add_ticker_tables_to_replication('test1');
SELECT set_name, set_reloid
FROM pglogical_ticker.rep_set_table_wrapper() rst
INNER JOIN pglogical.replication_set rs USING (set_id)
WHERE set_name = 'test1'
ORDER BY set_name, set_reloid::TEXT; 

--tables are extension members
DROP TABLE pglogical_ticker.test1;
