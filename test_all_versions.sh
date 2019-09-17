#!/bin/bash

set -eu

orig_path=$PATH
newest_version=1.4

unset PGSERVICE

set_path() {
version=$1
export PATH=/usr/lib/postgresql/$version/bin:$orig_path
}

get_port() {
version=$1
pg_lsclusters | awk -v version=$version '$1 == version { print $3 }'
}

make_and_test() {
version=$1
from_version=${2:-$newest_version}
set_path $version
make clean
sudo "PATH=$PATH" make uninstall
sudo "PATH=$PATH" make install
port=$(get_port $version)
PGPORT=$port psql postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'contrib_regression' AND pid <> pg_backend_pid()"
FROMVERSION=$from_version PGPORT=$port make installcheck

sigpg() {
sig=$1
echo "performing $sig"
sudo systemctl $sig postgresql@${version}-main
}

# Start without shared_preload_libraries
echo "Testing no shared_preload_libraries launch and restart"
sudo -u postgres sed -i "s/'pglogical,pglogical_ticker'/'pglogical'/g" /etc/postgresql/$version/main/postgresql.conf
sigpg restart

## Run the first 4 regression files which sets things up
echo "Seeding with first 4 regression scripts"
for f in sql/0[1-4]*; do
    PGPORT=$port psql contrib_regression -f $f > /dev/null
done

assert_ticker_running() {
PGPORT=$port psql contrib_regression -v "ON_ERROR_STOP" << 'EOM'
DO $$
BEGIN

IF NOT EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name LIKE 'pglogical_ticker%') THEN
    RAISE EXCEPTION 'No ticker running';
END IF;

END$$;
EOM
echo "PASS"
}

assert_ticker_not_running() {
PGPORT=$port psql contrib_regression -v "ON_ERROR_STOP" << 'EOM'
DO $$
BEGIN

IF EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name LIKE 'pglogical_ticker%') THEN
    RAISE EXCEPTION 'Ticker running';
END IF;

END$$;
EOM
echo "PASS"
}

ticker_check() {
echo "Launching ticker if not launched"
PGPORT=$port psql contrib_regression -v "ON_ERROR_STOP" << 'EOM' > /dev/null
SELECT pglogical_ticker.launch();
SELECT pg_sleep(1);
EOM
assert_ticker_running
echo "Terminating and expecting auto-restart"
PGPORT=$port psql contrib_regression -v "ON_ERROR_STOP" << 'EOM' > /dev/null
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name LIKE 'pglogical_ticker%';
SELECT pg_sleep(11);
EOM
assert_ticker_running
}
ticker_check

# Perform first load using shared_preload_libraries to set GUCs
sudo -u postgres sed -i "s/'pglogical'/'pglogical,pglogical_ticker'/g" /etc/postgresql/$version/main/postgresql.conf 
sudo -u postgres sed -i "\$apglogical_ticker.database = 'contrib_regression'" /etc/postgresql/$version/main/postgresql.conf
sigpg reload 
ticker_check

# Restart, now it should auto-launch
sigpg restart
sleep 11
ticker_check

echo "Testing soft crash restart"
PGPORT=$port psql contrib_regression -c "SELECT 'i filo postgres'::text, pg_sleep(10);" &
pid=`PGPORT=$port psql contrib_regression -Atq -c "SELECT pid FROM pg_stat_activity WHERE NOT pid = pg_backend_pid() AND query ~* 'i filo postgres'"`
echo "found pid $pid to kill"
sudo kill -9 $pid
sleep 12
ticker_check

sudo -u postgres sed -i "/pglogical_ticker.database/d" /etc/postgresql/$version/main/postgresql.conf
sigpg restart
sleep 11
assert_ticker_not_running
}

test_all_versions() {
from_version="$1"
cat << EOM

*******************FROM VERSION $from_version******************

EOM
make_and_test "9.5"
make_and_test "9.6"
make_and_test "10"
make_and_test "11"
}

test_all_versions "1.4"
test_all_versions "1.3"
