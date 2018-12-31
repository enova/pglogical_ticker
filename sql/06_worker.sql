SET client_min_messages TO WARNING;

--Discard the results here because pid will always be different
CREATE TEMP TABLE worker_pid AS
SELECT pglogical_ticker.launch() AS pid;

--Sleep 2 - should allow the worker to run the first time
SELECT pg_sleep(2);

--Capture the current source_time
DROP TABLE IF EXISTS checkit;
CREATE TEMP TABLE checkit AS
SELECT source_time FROM pglogical_ticker.test2;

--As of 1.0, naptime is 10 seconds, so the worker should run once again if we sleep for 11 
SELECT pg_sleep(11);

--Table should now have a greater value for source_time
SELECT (SELECT source_time FROM pglogical_ticker.test2) > (SELECT source_time FROM checkit) AS time_went_up;

SELECT pg_cancel_backend(pid)
FROM worker_pid;

-- Give it time to die asynchronously
SELECT pg_sleep(2);

--Try the launch_if_repset_tables function
DROP TABLE worker_pid;
CREATE TEMP TABLE worker_pid AS
SELECT pglogical_ticker.launch_if_repset_tables() AS pid;
SELECT pg_sleep(2);

SELECT COUNT(1) FROM worker_pid WHERE pid IS NOT NULL;

SELECT pg_cancel_backend(pid)
FROM worker_pid;

--Test it does nothing with no tables
BEGIN;

CREATE OR REPLACE FUNCTION pglogical_ticker.rep_set_remove_table_wrapper(set_name name, relation regclass)
 RETURNS BOOLEAN 
 LANGUAGE plpgsql
AS $function$
/*****
This handles the rename of pglogical.replication_set_relation to pglogical_ticker.rep_set_table_wrapper from version 1 to 2
 */
DECLARE
    v_result BOOLEAN;
BEGIN

IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'replication_set_remove_table') THEN
    SELECT pglogical.replication_set_remove_table(set_name, relation) INTO v_result;

ELSEIF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'replication_set_remove_relation') THEN
    SELECT pglogical.replication_set_remove_relation(set_name, relation) INTO v_result; 

END IF;
RETURN v_result;

END;
$function$
;

SELECT pglogical_ticker.rep_set_remove_table_wrapper(rs.set_name, rstw.set_reloid)
FROM pglogical_ticker.rep_set_table_wrapper() rstw
INNER JOIN pglogical.replication_set rs USING (set_id);

DROP TABLE worker_pid;
CREATE TEMP TABLE worker_pid AS
SELECT pglogical_ticker.launch_if_repset_tables() AS pid;

SELECT COUNT(1) FROM worker_pid WHERE pid IS NOT NULL;

ROLLBACK;
