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

Although not strictly required, to get access to the configuration settings of
`pglogical_ticker` and to auto-launch the ticker on server restart or a soft crash,
add `pglogical_ticker` to `shared_preload_libraries` in your postgresql.conf file:
```
shared_preload_libraries = 'pglogical,pglogical_ticker' #... and whatever others you already may have
```

Once installed, simply run this on the provider and all subscribers:
```sql
CREATE EXTENSION pglogical_ticker;
```

### Deploy ticker tables
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

### Configuration
This is only supported if you have added `pglogical_ticker` in `shared_preload_libraries`
as noted above.

- `pglogical_ticker.database`: The database in which to launch the ticker (we currently
    have no need to support multiple databases, but may add that feature at a later time).
    The ticker will only auto-launch on restart if this setting is configured.
- `pglogical_ticker.naptime`: How frequently the ticker ticks - default 10 seconds
- `pglogical_ticker.restart_time`: How many seconds before the ticker auto-restarts, default 10.  This
    is also how long it will take to re-launch after a soft crash, for instance. Set this to
    -1 to disable.  **Be aware** that you cannot use this setting to prevent an already-launched
    ticker from restarting.  Only a server restart will take this new value into account for
    the ticker backend and prevent it from ever restarting, if that is your desired behavior.

### Launching the ticker
As of version 1.4, the ticker will automatically launch upon server load
if you have `pglogical_ticker` in `shared_preload_libraries`.

Otherwise, this function will launch the ticker, only if there is not already
one running:
```sql
SELECT pglogical_ticker.launch();

/**
It is better to use the following function instead, which automatically checks if
the system should have a ticker based on tables existing in replication.
(this assumes you don't want a replication stream open with no tables).
**/
SELECT pglogical_ticker.launch_if_repset_tables();
```

The background worker launched either by this function or upon server load will
run the function `pglogical_ticker.tick()` every n seconds according to `pglogical_ticker.naptime`. 

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

It could be improved to use a different username.  I would also like it to
be written so as to prevent any possibility of launching more than one worker,
which currently is only done through the exposed function in the docs `launch()`.

As of 1.4, I'm also interested in allowing a clean shutdown with exit code 0,
as well as (if safe enough) searching databases for the ticker as opposed to having
to configure `pglogical_ticker.database`.

The SQL files are maintained separately to make version control much
easier to see.  Make changes in these folders and then run
`pglogical_ticker-sql-maker.sh` to build the extension SQL files.
This script will need modification with any new release to properly
build new extension files based on any new changes.
