#!/bin/sh
set -x

HOST_ID=${HOSTNAME##*-}

[ -z "$DATADIR" ] && exit "Missing DATADIR variable" && exit 1

# https://github.com/docker-library/mariadb/commit/f76084f0f9dc13f29cce48c727440eb79b4e92fa#diff-b0fa4b30392406b32de6b8ffe36e290dR80
if [ ! -d "$DATADIR/mysql" ]; then
  echo "No database in $DATADIR; configuring $POD_NAME for initial start"

  if [ $HOST_ID -eq 0 ]; then
    sed -i 's|#init#wsrep_new_cluster=true#init#|wsrep_new_cluster=true|' /etc/mysql/conf.d/galera.cnf
    # ... should log:
    #[Note] WSREP: 'wsrep-new-cluster' option used, bootstrapping the cluster
    #[Note] WSREP: Setting initial position to 00000000-0000-0000-0000-000000000000:-1
  fi
fi

# https://github.com/docker-library/mariadb/blob/master/10.2/docker-entrypoint.sh#L62
mysqld --verbose --help --log-bin-index="$(mktemp -u)"
