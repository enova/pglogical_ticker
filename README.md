## pglogical_ticker

Periodically churn an in-replication table using a Postgres background
worker to get replication time from standpoint of pglogical provider.

# How to use pglogical_ticker

### Installation

The functionality of this requires postgres 9.5+ and a working install of
pglogical.

DEB available on official PGDG repository as postgresql-${PGSQL_VERSION}-pglogical-ticker.
See installation instruction on https://wiki.postgresql.org/wiki/Apt

Or to build from source:
```
make
make install
make installcheck # run regression suite
```

Once installed, simply run this on the provider and all subscribers:
```sql
CREATE EXTENSION pglogical_ticker;
```

### Deploy tables and launch ticker
Deploy the ticker tables. Run this command on the provider only, which
will use `pglogical.replicate_ddl_command` to send to subscriber.
```sql
SELECT pglogical_ticker.deploy_ticker_tables();
```
This will add a table for each replication_set.

For cascading replication, you can add existing tables to another
replication set, that belonging to your 2nd tier subscriber.  You pass
that set_name to the `deploy` function like so:
```sql
SELECT pglogical_ticker.deploy_ticker_tables('my_cascaded_set_name');
```

Add the ticker tables to replication:
```sql
SELECT pglogical_ticker.add_ticker_tables_to_replication();
```

Again, to add ticker tables to a cascaded replication set:
```sql
SELECT pglogical_ticker.add_ticker_tables_to_replication('my_cascaded_set_name');
```

For any more custom needs than this, you can freely add ticker tables to replication sets
as you choose to manually.

You can manually try the tick() function if you so choose:
```sql
SELECT pglogical_ticker.tick();
```

TO LAUNCH THE BACKGROUND WORKER:
```sql
SELECT pglogical_ticker.launch();

/**
It is better to use this function always, which automatically checks if
the system should have a ticker based on tables existing in replication.
(this assumes you don't want a replication stream open with no tables).

This function is very useful if you want to just blindly run the function
to launch the ticker if it needs to be launched, i.e. after a restart.
**/
SELECT pglogical_ticker.launch_if_repset_tables();
```

This will run the function `pglogical_ticker.tick()` every 10 seconds.

Be sure to use caution in monitoring deployment and running of these background
worker processes.

To view all ticker tables at once, there are functions you can run to view
tables on both provider and subscriber:

Tables by replication set (provider):
```sql
SELECT * FROM pglogical_ticker.all_repset_tickers(); 
```

Tables by pglogical subscription (subscriber):
```sql
SELECT * FROM pglogical_ticker.all_subscription_tickers(); 
```

# For Developers
Help is always wanted to review and improve the BackgroundWorker module.
It is directly based on `worker_spi` from Postgres' test suite.

It could be improved to take arguments for naptime and also a different
username.  I would also like it to be written so as to prevent any 
possibility of launching more than one worker, which currently is only
done through the exposed function in the docs `launch()`.

The SQL files are maintained separately to make version control much
easier to see.  Make changes in these folders and then run
`pglogical_ticker-sql-maker.sh` to build the extension SQL files.
This script will need modification with any new release to properly
build new extension files based on any new changes.
