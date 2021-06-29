#!/bin/bash
set -x
[ "$(pwd)" != "/etc/mysql/conf.d" ] && cp * /etc/mysql/conf.d/

HOST_ID=${HOSTNAME##*-}

STATEFULSET_SERVICE=$(dnsdomainname -d)
POD_FQDN=$(dnsdomainname -A)

echo "This is pod $HOST_ID ($POD_FQDN) for statefulset $STATEFULSET_SERVICE"

[ -z "$WSREP_CLUSTER_ADDRESS" ] && echo "Missing WSREP_CLUSTER_ADDRESS env" && exit 1
sed -i "s|^#init-wsrep#.*|wsrep_cluster_address=$WSREP_CLUSTER_ADDRESS|" /etc/mysql/conf.d/galera.cnf

[ -z "$DATADIR" ] && exit "Missing DATADIR variable" && exit 1

SUGGEST_EXEC_COMMAND="kubectl --namespace=$POD_NAMESPACE exec -c init-config $POD_NAME --"

function wsrepNewCluster {
  sed -i 's|^#init-new-cluster#||' /etc/mysql/conf.d/galera.cnf
}

function wsrepRecover {
  sed -i 's|^#init-recover#||' /etc/mysql/conf.d/galera.cnf
}

function wsrepForceBootstrap {
  sed -i 's|safe_to_bootstrap: 0|safe_to_bootstrap: 1|' /data/db/grastate.dat
}

[[ $STATEFULSET_SERVICE = mariadb.* ]] || echo "WARNING: unexpected service name $STATEFULSET_SERVICE, Peer detection below may fail falsely."

if [ $HOST_ID -eq 0 ]; then
  echo "This is the 1st statefulset pod. Checking if the statefulset is down ..."
  getent hosts mariadb-ready
  [ $? -eq 2 ] && {
    # https://github.com/docker-library/mariadb/commit/f76084f0f9dc13f29cce48c727440eb79b4e92fa#diff-b0fa4b30392406b32de6b8ffe36e290dR80
    if [ ! -d "$DATADIR/mysql" ]; then
      echo "No database in $DATADIR; configuring $POD_NAME for initial start"
      wsrepNewCluster
    else
      set +x
      echo "----- ACTION REQUIRED -----"
      echo "No peers found, but data exists. To start in wsrep_new_cluster mode, run:"
      echo "  $SUGGEST_EXEC_COMMAND touch /tmp/confirm-new-cluster"
      echo "Or to start in recovery mode, to see replication state, run:"
      echo "  $SUGGEST_EXEC_COMMAND touch /tmp/confirm-recover"
      echo "Or to force bootstrap on this node, potentially losing writes, run:"
      echo "  $SUGGEST_EXEC_COMMAND touch /tmp/confirm-force-bootstrap"
      #echo "    NOTE This bypasses the following warning from new cluster mode:"
      #echo "    It may not be safe to bootstrap the cluster from this node. It was not the last one to leave the cluster and may not contain all the updates. To force cluster bootstrap with this node, edit the grastate.dat file manually and set safe_to_bootstrap to 1 ."
      echo "Or to try a regular start (for example after recovery + manual intervention), run:"
      echo "  $SUGGEST_EXEC_COMMAND touch /tmp/confirm-resume"
      if [ ! -z "$AUTO_RECOVERY_MODE" ]; then
        echo "The AUTO_RECOVERY_MODE env was set to $AUTO_RECOVERY_MODE, will trigger that choice"
        touch /tmp/$AUTO_RECOVERY_MODE
      else
        echo "Waiting for response ..."
      fi
      while [ ! -f /tmp/confirm-resume ]; do
        if [ "$AUTO_NEW_CLUSTER" = "true" ]; then
          echo "The AUTO_NEW_CLUSTER env was set to $AUTO_NEW_CLUSTER, will proceed without confirmation"
          echo "NOTE this env is deprecated, use AUTO_RECOVERY_MODE instead"
          wsrepNewCluster
          touch /tmp/confirm-resume
        elif [ -f /tmp/confirm-new-cluster ]; then
          echo "Confirmation received. Resuming new cluster start ..."
          wsrepNewCluster
          touch /tmp/confirm-resume
        elif [ -f /tmp/confirm-force-bootstrap ]; then
          echo "Forcing bootstrap on this node ..."
          wsrepForceBootstrap
          touch /tmp/confirm-new-cluster
        elif [ -f /tmp/confirm-recover ]; then
          echo "Confirmation received. Resuming in recovery mode."
          echo "Note: to start the other pods you need to edit OrderedReady and add a command: --wsrep-recover"
          wsrepRecover
          touch /tmp/confirm-resume
        fi
        sleep 1
      done
      rm /tmp/confirm-*
      set -x
    fi
  }
else
  getent hosts mariadb-ready
  [ $? -eq 2 ] && {
    echo "This is NOT the 1st statefulset pod. Must not go up as primary."
    echo "Found no ready pods. Will exit to trigger a crash loop back off."
    exit 1
  }
fi

# https://github.com/docker-library/mariadb/blob/master/10.2/docker-entrypoint.sh#L62
mysqld --verbose --help --log-bin-index="$(mktemp -u)" | tee /tmp/mariadb-start-config | grep -e ^version -e ^datadir -e ^wsrep -e ^binlog -e ^character-set -e ^collation
