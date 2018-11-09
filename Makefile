# pglogical_ticker/Makefile

MODULES = pglogical_ticker
REGRESS :=  01_create_ext 02_setup 03_deploy 04_add_to_rep \
            05_tick 06_worker 07_handlers 08_reentrance \
            09_1_2_tests 99_cleanup

EXTENSION = pglogical_ticker
DATA = pglogical_ticker--1.0.sql pglogical_ticker--1.0--1.1.sql \
        pglogical_ticker--1.1.sql pglogical_ticker--1.1--1.2.sql \
        pglogical_ticker--1.2.sql pglogical_ticker--1.2--1.3.sql \
        pglogical_ticker--1.3.sql
PGFILEDESC = "pglogical_ticker - Have an accurate view of pglogical replication delay"

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Prevent unintentional inheritance of PGSERVICE while running regression suite
# with make installcheck.  We typically use PGSERVICE in our shell environment but
# not for dev. Require instead explicit PGPORT= or PGSERVICE= to do installcheck
unexport PGSERVICE
