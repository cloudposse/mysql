#!/bin/bash
set -e

MYSQL_BOOTSTRAP_SQL="/tmp/bootstrap.sql"

# read DATADIR from the MySQL config
DATADIR="$(mysqld --verbose --help 2>/dev/null | awk '$1 == "datadir" { print $2; exit }')"

if [ "${1:0:1}" = '-' ] || [ $# -eq 0 ]; then
	set -- mysqld "$@"
fi
echo "ENTRYPOINT: $@"

chown -R mysql:mysql "$DATADIR"

if [ "$1" = 'mysqld' ]; then
	
	if [ -d "$DATADIR/mysql" ]; then
    echo " * Detected existing install; attempting upgrade..."
    "$@" --skip-networking  --skip-grant-tables &
    mysql_pid=$!
    echo -n "Starting mysqld"
    until mysqladmin -u"root" ping &>/dev/null; do
      echo -n "."; sleep 0.2
    done
    /usr/bin/mysql_upgrade || true
    /usr/bin/mysqlrepair --all-databases
    time mysqladmin -u"root" shutdown
    wait $mysql_pid
  else
    echo " * Detected fresh install"

    rm -f "$MYSQL_BOOTSTRAP_SQL" 
    # Delete extraneous dbs
    echo "DROP DATABASE IF EXISTS test;" >> "$MYSQL_BOOTSTRAP_SQL"
    echo "DROP USER IF EXISTS 'mysql.sys@localhost'@'localhost';" >> "$MYSQL_BOOTSTRAP_SQL"
    echo "DROP USER IF EXISTS 'root'@'localhost';" >> "$MYSQL_BOOTSTRAP_SQL"
    echo "DROP USER IF EXISTS 'root'@'%';" >> "$MYSQL_BOOTSTRAP_SQL"
    echo 'FLUSH PRIVILEGES ;' >> "$MYSQL_BOOTSTRAP_SQL"

    # Create the schema
    if [ -n "$MYSQL_DATABASE" ]; then
      echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;" >> "$MYSQL_BOOTSTRAP_SQL"
    fi
		
		echo " * Initializing db in $DATADIR with $MYSQL_BOOTSTRAP_SQL..."
		time mysqld --initialize-insecure --datadir="$DATADIR" --init-file="$MYSQL_BOOTSTRAP_SQL"
	
    if [ -z "$MYSQL_DUMP" ]; then
      if [ -f "$DATADIR/mysqldump.sql" ]; then
        MYSQL_DUMP="$DATADIR/mysqldump.sql";
      elif [ -f "/var/lib/mysqldump.sql" ]; then
        MYSQL_DUMP="/var/lib/mysqldump.sql";
      fi
    fi

    if [ -n "$MYSQL_DUMP" ]; then
      echo " * Importing $MYSQL_DUMP"
      # Start the database first in the background
      "$@" --skip-networking --skip-grant-tables &
      mysql_pid=$!
      echo -n "Starting mysqld"
      until mysqladmin -u"root" ping &>/dev/null; do
        echo -n "."; sleep 0.2
      done
      echo
      echo "Populating db $MYSQL_DATABASE from $MYSQL_DUMP"
      time mysql -u"root" "$MYSQL_DATABASE" < "$MYSQL_DUMP"
      # Shut the database back down
      time mysqladmin -u"root" shutdown
      wait $mysql_pid
    fi
	fi
fi

chown -R mysql:mysql "$DATADIR"

if [ -n "$MYSQL_INIT_SQL" ]; then
  echo " * Writing $MYSQL_INIT_SQL..."
  # These statements _must_ be on individual lines, and _must_ end with
  # semicolons (no line breaks or comments are permitted).
  # TODO proper SQL escaping on ALL the things D:

  if [ -z "$MYSQL_ROOT_PASSWORD" -a -z "$MYSQL_ALLOW_EMPTY_PASSWORD" ]; then
    echo >&2 'error: database is uninitialized and MYSQL_ROOT_PASSWORD not set'
    echo >&2 '  Did you forget to add -e MYSQL_ROOT_PASSWORD=... ?'
    exit 1
  fi

  rm -f "$MYSQL_INIT_SQL"

  # Setup accounts
  echo "CREATE USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';" >> "$MYSQL_INIT_SQL"
  echo "GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION;" >> "$MYSQL_INIT_SQL"

  if [ "$MYSQL_USER" -a "$MYSQL_PASSWORD" ]; then
    echo "DROP USER IF EXISTS '$MYSQL_USER'@'%';" >> "$MYSQL_INIT_SQL"
    echo 'FLUSH PRIVILEGES ;' >> "$MYSQL_INIT_SQL"
    echo "CREATE USER '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD' ;" >> "$MYSQL_INIT_SQL"
    
    if [ -n "$MYSQL_DATABASE" ]; then
      echo "GRANT ALL ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%' ;" >> "$MYSQL_INIT_SQL"
    fi
  fi

  echo 'FLUSH PRIVILEGES ;' >> "$MYSQL_INIT_SQL"
	set -- "$@" --init-file="$MYSQL_INIT_SQL"
fi

if [ -n "$MYSQL_CLIENT_CNF" ]; then
  echo " * Writing $MYSQL_CLIENT_CNF"
  printf "[client]\nuser=%s\npassword=%s\n" "root" "$MYSQL_ROOT_PASSWORD" > "$MYSQL_CLIENT_CNF"
  chmod 600 "$MYSQL_CLIENT_CNF"
fi

echo " * Starting mysql with '$@'"
exec "$@"
