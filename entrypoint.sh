#!/bin/bash
set -e

echo "ENTRYPOINT: $@"
if [ "${1:0:1}" = '-' ]; then
	set -- mysqld "$@"
fi

echo "Attempting upgrade..."
"$@" --skip-networking  --skip-grant-tables &
mysql_pid=$!
echo -n "Starting mysqld"
until mysqladmin -u"root" ping &>/dev/null; do
  echo -n "."; sleep 0.2
done
/usr/bin/mysql_upgrade || true
time mysqladmin -u"root" shutdown
wait $mysql_pid


if [ -n "$INIT_SQL" ]; then
  echo "Writing $INIT_SQL..."
  # These statements _must_ be on individual lines, and _must_ end with
  # semicolons (no line breaks or comments are permitted).
  # TODO proper SQL escaping on ALL the things D:

  if [ -z "$MYSQL_ROOT_PASSWORD" -a -z "$MYSQL_ALLOW_EMPTY_PASSWORD" ]; then
    echo >&2 'error: database is uninitialized and MYSQL_ROOT_PASSWORD not set'
    echo >&2 '  Did you forget to add -e MYSQL_ROOT_PASSWORD=... ?'
    exit 1
  fi

  rm -f "$INIT_SQL"

  # Basics

  # Setup root
  echo "DROP USER IF EXISTS 'root'@'%';" >> "$INIT_SQL"
  echo 'FLUSH PRIVILEGES ;' >> "$INIT_SQL"
  echo "CREATE USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';" >> "$INIT_SQL"
  echo "GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION;" >> "$INIT_SQL"

  # Delete extraneous dbs
  echo "DROP DATABASE IF EXISTS test;" >> "$INIT_SQL"

  # Create the schema
  if [ -n "$MYSQL_DATABASE" ]; then
    echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;" >> "$INIT_SQL"
  fi

  if [ "$MYSQL_USER" -a "$MYSQL_PASSWORD" ]; then
    echo "DROP USER IF EXISTS '$MYSQL_USER'@'%';" >> "$INIT_SQL"
    echo 'FLUSH PRIVILEGES ;' >> "$INIT_SQL"
    echo "CREATE USER '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD' ;" >> "$INIT_SQL"
    
    if [ "$MYSQL_DATABASE" ]; then
      echo "GRANT ALL ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%' ;" >> "$INIT_SQL"
    fi
  fi

  echo 'FLUSH PRIVILEGES ;' >> "$INIT_SQL"
	set -- "$@" --init-file="$INIT_SQL"
fi

if [ "$1" = 'mysqld' ]; then
	# read DATADIR from the MySQL config
	DATADIR="$(mysqld --verbose --help 2>/dev/null | awk '$1 == "datadir" { print $2; exit }')"
	
	if [ ! -d "$DATADIR/mysql" ]; then
    echo "Detected fresh install"
		
		echo 'Initializing db...'
		time mysql --initialize-insecure --datadir="$DATADIR"
		
    if [ -f "$DATADIR/mysqldump.sql" ]; then
      # Start the database first in the background
      "$@" --skip-networking &
      mysql_pid=$!
      echo -n "Starting mysqld"
      until mysqladmin -u"root" -p"$MYSQL_ROOT_PASSWORD" ping &>/dev/null; do
        echo -n "."; sleep 0.2
      done
      echo
      echo "Populating db $MYSQL_DATABASE from $DATADIR/mysqldump.sql"
      time mysql -u"root" -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" < "$DATADIR/mysqldump.sql"
      # Shut the database back down
      time mysqladmin -u"root" -p"$MYSQL_ROOT_PASSWORD" shutdown
      wait $mysql_pid
    fi
	fi
	chown -R mysql:mysql "$DATADIR"
fi

echo "Starting mysql with '$@'"
exec "$@"
