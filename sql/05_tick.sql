SET client_min_messages TO WARNING;

--Verify manual usage of tick function
SELECT pglogical_ticker.tick();
DROP TABLE IF EXISTS checkit;
CREATE TEMP TABLE checkit AS
SELECT * FROM pglogical_ticker.test1;
SELECT pglogical_ticker.tick();
SELECT (SELECT source_time FROM pglogical_ticker.test1) > (SELECT source_time FROM checkit) AS time_went_up;
SELECT pglogical_ticker.tick();

SELECT provider_name, set_name, source_time IS NOT NULL AS source_time_is_populated FROM pglogical_ticker.all_repset_tickers();
--This just is going to return nothing because no subscriptions exist.  Would be nice to figure out how to test that.
SELECT provider_name, set_name, source_time IS NOT NULL AS source_time_is_populated FROM pglogical_ticker.all_subscription_tickers();
