#!/bin/bash

#
# Copyright 2025
# Turnitin, LLC
#

# For colourizing pretend mode output
VT_yellow=$(echo -e "\033[38;5;11m")
VT_red=$(echo -e "\033[38;5;9m")
VT_reset=$(echo -e "\033[0m")

say () {
    echo "${VT_yellow}$*${VT_reset}"
}

yell () {
    echo "${VT_red}$*${VT_reset}"
}

oops () {
    yell "FAILED"
    exit 1
}

usage () {
    echo "$0 [<OPTIONS>]"
    echo "    -a                             Build out logical replica with 'ALL TABLES'"
    echo "                                   rather than an explicit table list."
    echo "                                   Default: false"
    echo "    -c                             Skip primary key check. Do not warn about tables that will cause"
    echo "                                   logical replay to fail on UPDATE."
    echo "                                   Default: false"
    echo "    -b <postgres binary directory> The path to postgres binaries you wish to use"
    echo "                                   Default: use the PATH from the environment"
    echo "    -d <publisher database name>   The publisher database to replicate from"
    echo "                                   *Required*"
    echo "    -D <subscriber database name>  The subscriber database to replicate to"
    echo "                                   Default: Same as publisher database name"
    echo "    -e                             Use existing subscriber database"
    echo "                                   Default: false"
    echo "    -f                             Drop and recreate subscriber database if it already exists"
    echo "                                   Cannot be used in conjunction with the -e flag"
    echo "    -g                             Migrate database settings like search_path and timezone. User"
    echo "                                   specific settings are not migrated."
    echo "                                   Default: false"
    echo "                                   WARNING: This option has been tested with search_path and"
    echo "                                   timezone. Unpredictable results may occur if database sets"
    echo "                                   other custom parameters. Use with care."
    echo "    -h <publisher host name>       The publisher host to replicate from"
    echo "                                   *Required*"
    echo "    -H <subscriber host name>      The subscriber host to replicate to"
    echo "    -k                             Skip schema initialization on the subscriber. Skipping"
    echo "                                   schema initialization may only be used with the -e flag"
    echo "                                   Default: false"
    echo "    -l                             Use pg_dumpall to import roles and passwords from the publication"
    echo "                                   database. The user being used to connect to the subscriber"
    echo "                                   database must already exist, and no attempt is made to issue"
    echo "                                   CREATE or ALTER statements for that user"
    echo "                                   Default: false"
    echo "                                   WARNING: No checking is done to ensure users do not already exist"
    echo "                                   on the subscriber node."
    echo "    -L                             Use pg_dumpall with the --no-role-passwords to import roles from"
    echo "                                   the publication database. Also remove any CREATE or ALTER commands"
    echo "                                   for users starting with 'rds' for RDS compatibility"
    echo "                                   Default: false"
    echo "                                   WARNING: No checking is done to ensure users do not already exist"
    echo "                                   on the subscriber node."
    echo "    -n                             Name of the publication to subscribe to. If the publication"
    echo "                                   does not exist, a new publication for all tables in the"
    echo "                                   database will be created. Whether or not an existing publication"
    echo "                                   is used as-is or recreated is controlled by the -r flag"
    echo "    -m                             Make the subscription name match the publication name. Useful for"
    echo "                                   systems which long hostnames that exceed the subscription name"
    echo "                                   length, resulting in trimming."
    echo "                                   Default: false"
    echo "    -p <publisher port number>     The port to use when connecting to the publisher database"
    echo "                                   Default: 5432"
    echo "    -P <subscriber port number>    The port to use when connecting to the subscriber database"
    echo "    -r                             Drop and recreate the publication if it exists"
    echo "                                   Default: false"
    echo "    -s <schema file>               The schema to use when setting up the subscriber database"
    echo "                                   Default: Dump from publisher"
    echo "    -T                             Exclude tables matching pattern from the publication"
    echo "                                   Default: Include all tables"
    echo "    -u <publisher user name>       The user to use when connecting to the publisher database"
    echo "                                   Default: postgres"
    echo "    -U <subscriber user name>      The user to use when connecting to the subscriber database"
    echo "                                   Default: Same as publisher user"
    echo "    -w                             Include user credentials in the connection string used by the"
    echo "                                   SUBSCRIPTION. This is needed in aws where the host's pgpass"
    echo "                                   credentials cannot be used."
    echo "                                   Default: false"
    echo "                                   WARNING: Not safe if your password has quote characters."
    echo "    -?                             Get help"
    exit 1;
}

# Set some defaults
ALL_TABLES=0
USE_EXISTING=0
USE_CREDS=0
FORCE_RECREATION=0
SKIP_SCHEMA_INIT=0
SKIP_PK_CHECK=0
PUBLISHER_PORT=5432
PUBLISHER_USER=postgres
RECREATE_PUBLICATION=0
SUBSCRIPTION_MATCHES_PUBLICATION_NAME=0
PG_DUMPALL=0
DUMP_OPTS=0
MIGRATE_SETTINGS=0

# Do the initial argument processing
while getopts "?ab:cd:D:efgh:H:klLn:mp:P:rs:T:u:U:w" o; do
  case "${o}" in
    '?')
      usage
      ;;
    a)
      ALL_TABLES=1
      ;;
    b)
      PG_BINPATH=${OPTARG}
      ;;
    c)
      SKIP_PK_CHECK=${OPTARG}
      ;;
    d)
      PUBLISHER_DB=${OPTARG}
      ;;
    D)
      SUBSCRIBER_DB=${OPTARG}
      ;;
    e)
      USE_EXISTING=1
      ;;
    f)
      FORCE_RECREATION=1
      ;;
    g)
      MIGRATE_SETTINGS=1
      ;;
    h)
      PUBLISHER_HOST=${OPTARG}
      ;;
    H)
      SUBSCRIBER_HOST_ARG="-h ${OPTARG}"
      SUBSCRIBER_HOST="${OPTARG}"
      ;;
    k)
      SKIP_SCHEMA_INIT=1
      ;;
    l)
      PG_DUMPALL=1
      ;;
    L)
      PG_DUMPALL=1
      DUMP_OPTS=1
      ;;
    n)
      PUBLICATION_NAME=${OPTARG}
      ;;
    m)
      SUBSCRIPTION_MATCHES_PUBLICATION_NAME=1
      ;;
    p)
      PUBLISHER_PORT=${OPTARG}
      ;;
    P)
      SUBSCRIBER_PORT_ARG="-p ${OPTARG}"
      ;;
    r)
      RECREATE_PUBLICATION=1
      ;;
    s)
      SCHEMA_FILE=${OPTARG}
      ;;
    T)
      TABLE_EXCLUSION_PATTERN=${OPTARG}
      ;;
    u)
      PUBLISHER_USER=${OPTARG}
      ;;
    U)
      SUBSCRIBER_USER=${OPTARG}
      ;;
    w)
      USE_CREDS=1
      ;;
    *)
      echo -e "Unknown option\n"
      usage
      ;;
  esac
done
shift $((OPTIND-1))

#
# Sanity checks & Defaults that are derived from other settings
#

# Check postgres binary path
if [ ! -z "$PG_BINPATH" ]
then
    # Add trailing / if missing
    if [[ ! $PG_BINPATH =~ '/$' ]]
    then
        PG_BINPATH="$PG_BINPATH/"
    fi
    # Ensure we've been given a directory and it has things that look like
    # postgres utilities in it
    if [ ! -d "$PG_BINPATH" ]
    then
        yell "'$PG_BINPATH' does not appear to be a directory."
        exit 1
    fi
    if [[ ! -f "$PG_BINPATH/psql" || ! -f "$PG_BINPATH/pg_dump" ]]
    then
        yell "Expected postgres binaries not found in '$PG_BINPATH' directory"
        exit 1
    fi
fi

# Bail if we've not been told who's doing the publishing
if [[ -z "$PUBLISHER_HOST" || -z "$PUBLISHER_DB" ]]
then
    yell "The -d and -h options are required."
    usage
fi

# Set subscriber database and user name if missing
if [ -z "$SUBSCRIBER_DB" ]
then
    SUBSCRIBER_DB=$PUBLISHER_DB
fi

if [ -z "$SUBSCRIBER_USER" ]
then
    SUBSCRIBER_USER=$PUBLISHER_USER
fi

# If someone has spaces in their usernames, they like their life
# to be hard and don't need this script 
if [[ $PUBLISHER_USER =~ ' ' || $SUBSCRIBER_USER =~ ' ' ]]
then
    yell "Usernames with spaces are not supported."
    exit 1
fi

# -e sanity check
if [[ "$USE_EXISTING" == "1"             \
      && "$FORCE_RECREATION" == "1"      \
   ]]
then
    yell "The -e option cannot be used with the -f option."
    usage
fi

# We can only skip schema initialization if the database already exists
if [[ "$SKIP_SCHEMA_INIT" == "1"         \
      && "$USE_EXISTING" != "1"          \
   ]]
then
    yell "The -k option may only be used with the -e option."
    usage
fi

# We cannot exclude tables if "all tables" stlye publications are being used
if [[ "$ALL_TABLES" == "1"                 \
          && ! -z $TABLE_EXCLUSION_PATTERN \
   ]]
then
    yell "Tables may not be excluded with the -T option when the -a option is being used."
    usage
fi

if [[ ! -z $TABLE_EXCLUSION_PATTERN             \
       && $TABLE_EXCLUSION_PATTERN =~ \$PAT\$   \
   ]]
then
    yell "Table exclusion pattern must not include the text '"'$PAT$'"'"
    usage
fi

# Unless we have been asked to skip the primary key check, scan
# the publisher database for tables with no primary keys and
# alert the user if found
if [[ "$SKIP_PK_CHECK" == "0" ]]
then
    # Fetch the list of tables with no primary keys
    NO_PK=$(psql -U $PUBLISHER_USER -d $PUBLISHER_DB -h $PUBLISHER_HOST -AXtc "
SELECT string_agg(tbl.table_schema || '.' || tbl.table_name, ', ')
FROM information_schema.tables tbl
WHERE table_type = 'BASE TABLE'
  AND table_schema NOT IN ('pg_catalog', 'information_schema')
  AND NOT EXISTS
      ( SELECT 1
        FROM pg_catalog.pg_index i
             JOIN pg_catalog.pg_class c ON i.indrelid = c.oid
             JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE i.indisprimary
              AND c.relname = tbl.table_name
              AND n.nspname = tbl.table_schema
      )")

    if [[ "$NO_PK" != "" ]]
    then
        yell WARNING:
        echo "The following tables in the publisher datatabase"\
             "'$PUBLISHER_DB' have no primary key and may not"\
             "behave properly with logical replication in all"\
             "circumstances. Consider Adding primary keys:"
        echo
        echo "    $NO_PK"
        echo
        printf "Type OK to continue anyway\n" && read IS_OK
        echo
        if [[ ! $IS_OK =~ ^(ok|OK)$ ]]
        then
            exit 1
        fi
    fi
fi

# If we've been given a schema file, ensure it exists
if [[ ! -z $SCHEMA_FILE && ! -f $SCHEMA_FILE ]]
then
    yell "'$SCHEMA_FILE' does not appear to exist."
    exit 1
fi

# Set a name for our publication is the user has not provided one
if [ -z $PUBLICATION_NAME ]
then
    if [ "$ALL_TABLES" == "1" ]
    then
        PUBLICATION_NAME=$(printf '%.50s_all_tables' $PUBLISHER_DB)
    else
        PUBLICATION_NAME=$(printf '%.42s_all_listed_tables' $PUBLISHER_DB)
    fi
fi

if [ "$SUBSCRIPTION_MATCHES_PUBLICATION_NAME" == "1" ]
then
    SUBSCRIPTION_NAME=$PUBLICATION_NAME
else
    if [ -z "$SUBSCRIBER_HOST" ]
    then
        SUBSCRIBER_HOST_LABEL=$( hostname -f | sed 's/[.-]/_/g' )
    else
        SUBSCRIBER_HOST_LABEL=$( echo $SUBSCRIBER_HOST | sed 's/[.-]/_/g' )
    fi
    SUBSCRIPTION_NAME=$(printf '%.63s' $(printf '%.40s_%s' $SUBSCRIBER_HOST_LABEL $PUBLICATION_NAME))
fi

# Test a connection to the publisher
CANSELECT=$("${PG_BINPATH}psql" -h $PUBLISHER_HOST -p $PUBLISHER_PORT \
                -U $PUBLISHER_USER -d $PUBLISHER_DB                   \
                -AXtc 'SELECT 1' 2>&1)
if [[ "$CANSELECT" != "1" ]]
then
    yell "Could not connect to the '$PUBLISHER_DB' database'" \
         "on '$PUBLISHER_HOST' port '$PUBLISHER_PORT' as user '$PUBLISHER_USER'"
    exit 1
fi

#
# Things that can result in changes on the publisher or subscriber databases start here
#

# If we're going to use the existing database on the subscriber, it needs to exist.
# If it exists and we've been told to create it, we need to also have the force option.
# If it exists and force has been given, do the drop.
CANSELECT=$("${PG_BINPATH}psql" $SUBSCRIBER_HOST_ARG $SUBSCRIBER_PORT_ARG \
                -U $SUBSCRIBER_USER -d $SUBSCRIBER_DB                     \
                -AXtc 'SELECT 1' 2>&1)
if [[ "$CANSELECT" != "1" ]]
then
    if [ "$USE_EXISTING" == "1" ]
    then
        yell "Could not connect to the subscriber database '$SUBSCRIBER_DB'" \
             "as user '$SUBSCRIBER_USER'"
        exit 1
    fi
else
    if [ "$USE_EXISTING" != "1" ]
    then
        if [ "$FORCE_RECREATION" != "1" ]
        then
            yell "The '$SUBSCRIBER_DB' database already exists on the subscriber." \
                 "Add -f to drop and recreate it."
            exit 1
        else
            say "Dropping existing '$SUBSCRIBER_DB' on subcriber host."
            "${PG_BINPATH}psql" $SUBSCRIBER_HOST_ARG $SUBSCRIBER_PORT_ARG \
                -U $SUBSCRIBER_USER -d postgres                           \
                -AXtc "DROP DATABASE $SUBSCRIBER_DB" || oops
        fi
    fi
fi

# Encourage users to bump up max_logical_replication_workers during the build out
LWORKERS=$("${PG_BINPATH}psql" $SUBSCRIBER_HOST_ARG $SUBSCRIBER_PORT_ARG \
               -U $SUBSCRIBER_USER -d postgres                           \
               -AXtc 'SHOW max_logical_replication_workers' 2>&1)
if [[ $LWORKERS -lt 5 ]]
then
    yell "Consider interrupting and increasing max_logical_replication_workers" \
         "to speed up initializiation."
    sleep 5
fi

# If we're not using the existing db, create the database on the subscriber node
if [ $USE_EXISTING != "1" ]
then
    say "Creating '$SUBSCRIBER_DB' on the subscriber node"
    "${PG_BINPATH}psql" $SUBSCRIBER_HOST_ARG $SUBSCRIBER_PORT_ARG \
        -U $SUBSCRIBER_USER -d postgres                           \
        -AXtc "CREATE DATABASE $SUBSCRIBER_DB" || oops
fi


# If we have been asked to deploy roles using pg_dumpall
if [ "$PG_DUMPALL" == "1" ]
then
    say "Importing the roles from Publisher database using pg_dumpall"
    if [ "$DUMP_OPTS" == "1" ]
    then
        "${PG_BINPATH}pg_dumpall" -h $PUBLISHER_HOST -p $PUBLISHER_PORT     \
            -U $PUBLISHER_USER -r --no-role-passwords                       \
            | grep -ve 'ALTER\|CREATE ROLE rds\|'$SUBSCRIBER_USER           \
            | grep -ve 'GRANT.*rds_superuser'                               \
            | "${PG_BINPATH}psql" $SUBSCRIBER_HOST_ARG $SUBSCRIBER_PORT_ARG \
            -U $SUBSCRIBER_USER -d $SUBSCRIBER_DB -X                        \
            || oops
    else
        "${PG_BINPATH}pg_dumpall" -h $PUBLISHER_HOST -p $PUBLISHER_PORT     \
            -U $PUBLISHER_USER -r                                           \
            | grep -ve 'ALTER\|CREATE ROLE '$SUBSCRIBER_USER                \
            | "${PG_BINPATH}psql" $SUBSCRIBER_HOST_ARG $SUBSCRIBER_PORT_ARG \
            -U $SUBSCRIBER_USER -d $SUBSCRIBER_DB -X                        \
            || oops
    fi
fi

# Init the subscriber schema
if [ "$SKIP_SCHEMA_INIT" == 0 ]
then
    if [ -z $SCHEMA_FILE ]
    then
        say "Cloning publisher schema on subscriber"
        "${PG_BINPATH}pg_dump" -h $PUBLISHER_HOST -p $PUBLISHER_PORT        \
            -U $PUBLISHER_USER -d $PUBLISHER_DB -s                          \
            | "${PG_BINPATH}psql" $SUBSCRIBER_HOST_ARG $SUBSCRIBER_PORT_ARG \
            -U $SUBSCRIBER_USER -d $SUBSCRIBER_DB -X                        \
            || oops
    else
        say "Initializing publisher schema using '$SCHEMA_FILE'"
        "${PG_BINPATH}psql" $SUBSCRIBER_HOST_ARG $SUBSCRIBER_PORT_ARG \
             -U $SUBSCRIBER_USER -d $SUBSCRIBER_DB -f $SCHEMA_FILE -X \
             || oops
    fi
fi

# Migrate the search_path settings if asked
if [ "$MIGRATE_SETTINGS" == "1" ]
then
    say "Importing database settings from the publisher database"

    # many timezone definitions have a /, so needs to be quoted when being
    # set on the subscriber db. Can't just throw quotes on all the time
    # though because if you quote the search path, for intstance, it will
    # make the search path have one entry matching the full list on the
    # publisher. Timezone is the only setting I've encountered so far that
    # requires quoting, but that doesn't mean others are not out there...
    ${PG_BINPATH}psql -h $PUBLISHER_HOST -p $PUBLISHER_PORT \
                      -U $PUBLISHER_USER -d $PUBLISHER_DB   \
                      -AXt <<EOF                            \
    | ${PG_BINPATH}psql $SUBSCRIBER_HOST_ARG $SUBSCRIBER_PORT_ARG \
                        -U $SUBSCRIBER_USER -d $SUBSCRIBER_DB -AXt
SELECT 'ALTER DATABASE $SUBSCRIBER_DB'
       || ' SET ' 
       || CASE WHEN settings ~ '/'
               THEN pg_catalog.regexp_replace(settings,
                                              '=(.*?)\$',
                                              '=''\\1'';'
                                             )
               ELSE settings || ';'
          END
FROM pg_db_role_setting pdrs
     JOIN pg_database d ON d.oid = pdrs.setdatabase
     JOIN unnest(pdrs.setconfig) AS settings ON true
WHERE d.datname = '$PUBLISHER_DB' AND setrole=0
EOF

fi

# Create the publication if needed
PUBLICATION_QUERY="SELECT pubname FROM pg_publication WHERE pubname = '$PUBLICATION_NAME'"
HAS_PUBLICATION=$("${PG_BINPATH}psql" -h $PUBLISHER_HOST -p $PUBLISHER_PORT \
                      -U $PUBLISHER_USER -d $PUBLISHER_DB                   \
                      -AXtc "$PUBLICATION_QUERY"
)

if [[ "$HAS_PUBLICATION" == "$PUBLICATION_NAME"
      && "$RECREATE_PUBLICATION" == 1 ]]
then
    say "Dropping existing publication"
    ${PG_BINPATH}psql -h $PUBLISHER_HOST -p $PUBLISHER_PORT \
                      -U $PUBLISHER_USER -d $PUBLISHER_DB   \
                      -AXtc "DROP PUBLICATION \"$PUBLICATION_NAME\""
    HAS_PUBLICATION=""
fi

if [[ ! "$HAS_PUBLICATION" == "$PUBLICATION_NAME" ]]
then
    if [ "$ALL_TABLES" == "1" ]
    then
        TABLE_CLAUSE="FOR ALL TABLES"
    else
        if [[ -z $TABLE_EXCLUSION_PATTERN ]]
        then
            TABLE_EXCLUDE_CLAUSE=""
        else
            TABLE_EXCLUDE_CLAUSE="AND c.relname !~ \$PAT\$$TABLE_EXCLUSION_PATTERN\$PAT\$"
        fi
        say "Fetching tables list from the publisher"
        TABLE_LIST=$("${PG_BINPATH}psql" -h $PUBLISHER_HOST -p $PUBLISHER_PORT \
            -U $PUBLISHER_USER -d $PUBLISHER_DB                                \
            -AXt 2>&1 <<EOF
WITH alltables AS (
  SELECT '"' || n.nspname || '"' || '.' || '"' || c.relname || '"' as tablename
  FROM pg_catalog.pg_class c
       LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind IN ('r','p','')
        AND n.nspname <> 'pg_catalog'
        AND n.nspname <> 'information_schema'
        AND n.nspname !~ '^pg_toast'
        $TABLE_EXCLUDE_CLAUSE
)
SELECT string_agg( tablename, ', ' )
FROM alltables
EOF
        )
        if [[ "$TABLE_LIST" =~ "ERROR:" ]]
        then
            yell "Failed to retreive list of tables in publisher database"
            exit 1
        fi
        if [[ -z $TABLE_LIST ]]
        then
            yell "Can't create a publication on an empty database"
            exit 1
        fi
        TABLE_CLAUSE="FOR TABLE $TABLE_LIST"
    fi
    say "Creating publication"
    "${PG_BINPATH}psql" -h $PUBLISHER_HOST -p $PUBLISHER_PORT  \
        -U $PUBLISHER_USER -d $PUBLISHER_DB                    \
        -AXtc "CREATE PUBLICATION $PUBLICATION_NAME $TABLE_CLAUSE" || oops
else
    say "Using existing publication"
fi

if [[ $USE_CREDS == "1" ]]
then
    say "Fetching credentials"
    PGPASSFILE=${PGPASSFILE:=~/.pgpass}
    # Look in $PGPASSFILE for the first entry that is valid for the publisher
    # database, then extract the password from that line
    PUBUSER_PASS=$(grep -e "^\($PUBLISHER_HOST\|\*\):\($PUBLISHER_PORT\|\*\):\($PUBLISHER_DB\|\*\):\($PUBLISHER_USER\|\*\):" \
                       $PGPASSFILE                                                                                           \
                       | head -n 1                                                                                           \
                       | sed 's/^[^:]\+:[^:]\+:[^:]\+:[^:]\+://'                                                             \
                       | sed 's/\\:/:/')

    # If no password was found, fail, though not having these creds should have
    # already caused failure
    if [[ -z $PUBUSER_PASS ]]
    then
        yell "No suitable credentials found!"
        oops
    fi

    SUBSCRIPTION_CREDS=" user=$PUBLISHER_USER password=$PUBUSER_PASS"
fi

# Create the subscription
# The slot must be created separately from the subscription to prevent
# the create subscription step from hanging when the publisher and subscriber
# databases are on the same node
say "Creating the subscription"
"${PG_BINPATH}psql" -h $PUBLISHER_HOST -p $PUBLISHER_PORT  \
    -U $PUBLISHER_USER -d $PUBLISHER_DB                    \
    -AXtc "SELECT pg_create_logical_replication_slot('$SUBSCRIPTION_NAME', 'pgoutput')" || oops
"${PG_BINPATH}psql" $SUBSCRIBER_HOST_ARG $SUBSCRIBER_PORT_ARG \
    -U $SUBSCRIBER_USER -d $SUBSCRIBER_DB -AXt <<EOF || oops
CREATE SUBSCRIPTION "$SUBSCRIPTION_NAME"
CONNECTION 'host=$PUBLISHER_HOST port=$PUBLISHER_PORT dbname=$PUBLISHER_DB $SUBSCRIPTION_CREDS'
PUBLICATION $PUBLICATION_NAME
WITH ( create_slot = false );
EOF

say "Complete"
