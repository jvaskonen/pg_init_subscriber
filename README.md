# Usage
```
pg_init_subscriber.sh [<OPTIONS>]
    -a                             Build out logical replica with 'ALL TABLES'
                                   rather than an explicit table list.
                                   Default: false
    -c                             Skip primary key check. Do not warn about tables that will cause
                                   logical replay to fail on UPDATE.
                                   Default: false
    -b <postgres binary directory> The path to postgres binaries you wish to use
                                   Default: use the PATH from the environment
    -d <publisher database name>   The publisher database to replicate from
                                   *Required*
    -D <subscriber database name>  The subscriber database to replicate to
                                   Default: Same as publisher database name
    -e                             Use existing subscriber database
                                   Default: false
    -f                             Drop and recreate subscriber database if it already exists
                                   Cannot be used in conjunction with the -e flag
    -g                             Migrate database settings like search_path and timezone. User
                                   specific settings are not migrated.
                                   Default: false
                                   WARNING: This option has been tested with search_path and
                                   timezone. Unpredictable results may occur if database sets
                                   other custom parameters. Use with care.
    -h <publisher host name>       The publisher host to replicate from
                                   *Required*
    -H <subscriber host name>      The subscriber host to replicate to
                                   Default: local socket
    -k                             Skip schema initialization on the subscriber. Skipping
                                   schema initialization may only be used with the -e flag
                                   Default: false
    -l                             Use pg_dumpall to import roles and passwords from the publication
                                   database. The user being used to connect to the subscriber
                                   database must already exist, and no attempt is made to issue
                                   CREATE or ALTER statements for that user
                                   Default: false
                                   WARNING: No checking is done to ensure users do not already exist
                                   on the subscriber node.
    -L                             Use pg_dumpall with the --no-role-passwords to import roles from
                                   the publication database. Also remove any CREATE or ALTER commands
                                   for users starting with 'rds' for RDS compatibility
                                   Default: false
                                   WARNING: No checking is done to ensure users do not already exist
                                   on the subscriber node.
    -n                             Name of the publication to subscribe to. If the publication
                                   does not exist, a new publication for all tables in the
                                   database will be created. Whether or not an existing publication
                                   is used as-is or recreated is controlled by the -r flag
    -m                             Make the subscription name match the publication name. Useful for
                                   systems which long hostnames that exceed the subscription name
                                   length, resulting in trimming.
                                   Default: false
    -p <publisher port number>     The port to use when connecting to the publisher database
                                   Default: 5432
    -P <subscriber port number>    The port to use when connecting to the subscriber database
    -r                             Drop and recreate the publication if it exists
                                   Default: false
    -s <schema file>               The schema to use when setting up the subscriber database
                                   Default: Dump from publisher
    -T                             Exclude tables matching pattern from the publication
                                   Default: Include all tables
    -u <publisher user name>       The user to use when connecting to the publisher database
                                   Default: postgres
    -U <subscriber user name>      The user to use when connecting to the subscriber database
                                   Default: Same as publisher user
    -w                             Include user credentials in the connection string used by the
                                   SUBSCRIPTION. This is needed in aws where the host's pgpass
                                   credentials cannot be used.
                                   Default: false
                                   WARNING: Not safe if your password has quote characters.
    -?                             Get help
```
# Setup
For this script to function, the system where the script is being run must be able to connect to both the publisher and subscriber databases as the user running the script. This is most easily accomplished with a `.pgpass` entry. The subscriber node must also be able to connect to the publisher database as the database user. Either a `.pgpass` file can be set up on the subscriber node, or the credentials can be embedded in the subscription configuration using the `-w` flag.
# Examples
## Clone a database
If all needed roles have already been created on the subscriber database, the schema can be cloned from the publisher and replication initated using the postgres user:
```
jvaskonen@zephaniah:~ % pg_init_subscriber.sh -h pub.example.com -d mines -H sub.example.com
jmiller@zephaniah:~ % pg_init_subscriber.sh -h pub.example.com -d mines -H sub.example.com -D mines2
Consider interrupting and increasing max_logical_replication_workers to speed up initializiation.
Creating 'mines' on the subscriber node
CREATE DATABASE
Cloning publisher schema on subscriber
SET
SET
SET
SET
SET
 set_config
------------

(1 row)

SET
SET
SET
SET
SET
SET
CREATE TABLE
ALTER TABLE
ALTER TABLE
CREATE TABLE
ALTER TABLE
ALTER TABLE
CREATE TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
ALTER TABLE
Fetching tables list from the publisher
Creating publication
CREATE PUBLICATION
Creating the subscription
(sub_example_com_mines_all_listed_tables,0/436CEEB8)
CREATE SUBSCRIPTION
Complete
```
## Cloning a database and roles
The script can also use `pg_dumpall` to recreate roles from the publisher on the scriber via the `-l` flag: `pg_init_subscriber.sh -h pub.example.com -d mines -H sub.example.com -l`<br>
Note: This can reset the credentials of the user the script is using to connect to the subscriber database.

## Using managed providers
Managed service providers typically block access to sensitive system tables such as `pg_shadow`, preventing `pg_dumpall` from accessing credentials. In such cases the `-L` flag may be used in place of the `-l` flag to create the roles without setting user credentials. Additionally, since you cannot set up a `.pgpass` file on the subscriber node for use connecting to the publisher, so the credentials must be included in the subscription. The `-w` flag can be used to instruct the script to extract credentials from the active `PGPASSFILE` and use them when creation the subscription. If using `-w`, including whitespace or quotation characters in your credentials is... brave. 
```
pg_init_subscriber.sh -h pub.example.com -d mines -H sub.example.com -D new_mines -L -w
```

## Keeping search_path and timezone settings
The `-g` flag can be used to dump the timezone and other `ALTER DATABASE` settings from the publisher node.
```
pg_init_subscriber.sh -h pub.example.com -d mines -H sub.example.com -g
```
## Changing schemas
In some cases, you may not want the schema on the publisher and subscriber to be identical. For instance, you could be converting integer columns to bigint, or you could be replicating to a reporting database where additional indexes are needed. In such cases, the `-s` flag may be used to provide an updated schema to be used on the subscriber.
```
pg_init_subscriber.sh -h pub.example.com -d mines -H sub.example.com -D bigint_mines -s bigint_mines_schema.sql
```
## Excluding tables
In some cases, it is desirable to exclude tables from the publication. For instance, you may want to exclude a schema versioning table since schema changes need to be applied to the publisher and subscriber independently. That can be accomplished with the `-T` flag.
Note:
  * The patterns are regular expressions, not the pattern syntax used by `pg_dump -T` and `\dt` in `psql`
  * Tables are only excluded from the publication. If the schema is being cloned, the tables will still be created on the subscriber database. If you do not wish to include the excluded tables on the subscriber, create a version of the schema without them and use the `-s` flag.
```
pg_init_subscriber.sh -h pub.example.com -d mines -H sub.example.com -D new_mines -T 'databasechangelog|schema_version'
```

## `ALL TABLES` publications
By default, the script creates publications that call out each table explicitly, which allows greater flexibility using `ALTER PUBLICATION`. The `-a` flag may be used to instead create an `ALL TABLES` publication. If that option is used, no tables may be excluded from the publication, and care must be taken to ensure the subscriber database has new table/column schema updates before the publisher attempts to replicate any changes involving them.
```
pg_init_subscriber.sh -h pub.example.com -d mines -H sub.example.com -a
```

## Starting over
Sometimes you don't do things correctly the first go around, and you just need to start over. If the subscription creation happened `psql -U <user> -h <subscriber node> -d <target db> -c 'DROP SUBSCRIPTION <subscription name'` (if you omit the `-c` the psql has handy tab complete). Afterwards:
```
pg_init_subscriber.sh -h pub.example.com -d mines -H sub.example.com -f -r -T 'table_you_forgot_to_exclude_the_first_time'
```
