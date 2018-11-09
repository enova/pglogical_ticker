SET client_min_messages TO WARNING;

--The _launch function is not supposed to be used directly
--This tests that stupid things don't do something really bad
SELECT pglogical_ticker._launch(9999999::OID) AS pid;

--Verify that it exits cleanly if the SQL within the worker errors out
--In this case, renaming the function will do it
ALTER FUNCTION pglogical_ticker.tick() RENAME TO tick_oops;
SELECT pglogical_ticker.launch();

ALTER FUNCTION pglogical_ticker.tick_oops() RENAME TO tick;

--Verify we can't start multiple workers - the second attempt should return NULL
--We know this is imperfect but so long as pglogical_ticker.launch is not executed
--at the same exact moment this is good enough insurance for now.
--Also, multiple workers still could be running without any bad side effects.

--Should be false
SELECT pglogical_ticker.launch() IS NULL AS pid;
SELECT pg_sleep(1);

--Should be true
SELECT pglogical_ticker.launch() IS NULL AS next_attempt_no_pid;

SELECT pg_cancel_backend(pid)
FROM pg_stat_activity
WHERE NOT pid = pg_backend_pid()
 AND query LIKE '%pglogical_ticker%';

SELECT pg_sleep(1);
SELECT COUNT(1) AS ticker_still_running
FROM pg_stat_activity
WHERE NOT pid = pg_backend_pid()
 AND query LIKE '%pglogical_ticker%';
