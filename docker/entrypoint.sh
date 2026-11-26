#!/bin/bash
set -euo pipefail

DATADIR="${MYSQL_DATADIR:-/data/mysql}"
MYSQL_DATABASE="${MYSQL_DATABASE:-folio}"
MYSQL_USER="${MYSQL_USER:-folio}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-folio}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-${MYSQL_PASSWORD}}"

mkdir -p "$DATADIR" /run/mysqld
chown -R mysql:mysql "$DATADIR" /run/mysqld 2>/dev/null || true

MYSQL_SOCKET="${MYSQL_SOCKET:-/run/mysqld/mysqld.sock}"

start_mysqld() {
  mysqld \
    --user=mysql \
    --datadir="$DATADIR" \
    --bind-address=127.0.0.1 \
    --port=3306 \
    --socket="$MYSQL_SOCKET" \
    --default-time-zone=+00:00 \
    "$@" &
  MYSQLD_PID=$!
}

wait_for_mysql() {
  local i=0
  while [ "$i" -lt 90 ]; do
    if mysqladmin --socket="$MYSQL_SOCKET" ping --silent 2>/dev/null; then
      return 0
    fi
    i=$((i + 1))
    sleep 1
  done
  echo "MariaDB failed to become ready" >&2
  exit 1
}

install_db() {
  if command -v mariadb-install-db >/dev/null 2>&1; then
    mariadb-install-db --user=mysql --datadir="$DATADIR" --auth-root-authentication-method=normal >/dev/null
  else
    mysql_install_db --user=mysql --datadir="$DATADIR" --auth-root-authentication-method=normal >/dev/null
  fi
}

if [ ! -d "$DATADIR/mysql" ]; then
  echo "Initializing MariaDB datadir at $DATADIR"
  install_db
  start_mysqld --skip-networking
  wait_for_mysql
  mysql --socket="$MYSQL_SOCKET" -uroot <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'localhost';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
  mysqladmin --socket="$MYSQL_SOCKET" -uroot -p"${MYSQL_ROOT_PASSWORD}" shutdown
  wait "$MYSQLD_PID" 2>/dev/null || true
fi

echo "Starting MariaDB"
start_mysqld
wait_for_mysql

export SPRING_DATASOURCE_URL="${SPRING_DATASOURCE_URL:-jdbc:mysql://127.0.0.1:3306/${MYSQL_DATABASE}?useUnicode=true&characterEncoding=UTF-8&connectionTimeZone=UTC}"
export SPRING_DATASOURCE_USERNAME="${SPRING_DATASOURCE_USERNAME:-${MYSQL_USER}}"
export SPRING_DATASOURCE_PASSWORD="${SPRING_DATASOURCE_PASSWORD:-${MYSQL_PASSWORD}}"

mkdir -p /data/logs
export FOLIO_LOG_FILE="${FOLIO_LOG_FILE:-/data/logs/folio.log}"
export TZ="${TZ:-Asia/Shanghai}"

echo "Starting Folio"
exec java -Duser.timezone="${TZ}" ${JAVA_OPTS:-} -jar /app/folio.jar
