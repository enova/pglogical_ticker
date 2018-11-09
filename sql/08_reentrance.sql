WITH sets AS (
SELECT 'test'||generate_series AS set_name
FROM generate_series(9,10)
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

SET client_min_messages TO warning;
ALTER EXTENSION pglogical_ticker UPDATE;

SELECT pglogical_ticker.deploy_ticker_tables();
SELECT pglogical_ticker.add_ticker_tables_to_replication();
