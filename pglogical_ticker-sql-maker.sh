#!/usr/bin/env bash

set -eu

last_version=1.3
new_version=1.4
last_version_file=pglogical_ticker--${last_version}.sql
new_version_file=pglogical_ticker--${new_version}.sql
update_file=pglogical_ticker--${last_version}--${new_version}.sql

rm -f $update_file
rm -f $new_version_file

create_update_file_with_header() {
cat << EOM > $update_file
/* $update_file */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pglogical_ticker" to load this file. \quit

EOM
}

add_sql_to_file() {
sql=$1
file=$2
echo "$sql" >> $file
}

add_file() {
s=$1
d=$2
(cat "${s}"; echo; echo) >> "$d"
}

create_update_file_with_header

# Add view and function changes
add_file functions/pglogical_ticker.launch.sql $update_file

# Only copy diff and new files after last version, and add the update script
touch $update_file
cp $last_version_file $new_version_file
#cat $update_file >> $new_version_file
