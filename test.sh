#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -eo pipefail
DIR="$(dirname $0)"

export KUBECONFIG=$DIR/kubeconfig

show_cluster_size() {
  kubectl -n mysqltest exec -c mariadb-galera ystack-mariadb-galera-0 -- mysql -u root "-pTESTROOT" -N -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 
}

k3d cluster create mysqltest --agents 3 --agents-memory 512M

kubectl create namespace mysqltest

# With >1 replicas this leads to split brain despite ./base/bootstrap-no.yaml
#kubectl -n mysqltest apply -k ./base

kubectl -n mysqltest apply -k ./base-bootstrap
kubectl -n mysqltest rollout status statefulset/ystack-mariadb-galera

show_cluster_size

kubectl -n mysqltest apply -k ./base
kubectl -n mysqltest rollout status statefulset/ystack-mariadb-galera

show_cluster_size

kubectl -n mysqltest scale --replicas=2 statefulset/ystack-mariadb-galera
kubectl -n mysqltest rollout status statefulset/ystack-mariadb-galera

show_cluster_size

kubectl -n mysqltest scale --replicas=4 statefulset/ystack-mariadb-galera
kubectl -n mysqltest rollout status statefulset/ystack-mariadb-galera

show_cluster_size

kubectl -n mysqltest delete --wait=false pod/ystack-mariadb-galera-1
sleep 1
show_cluster_size
kubectl -n mysqltest wait --for=condition=Ready --timeout=60s pod/ystack-mariadb-galera-1
show_cluster_size

# With curl from somewhere we wouldn't need a pod name for show_cluster_size
# curl -s http://ystack-mariadb-galera-metrics.mysqltest:9104/metrics | grep cluster_size
#kubectl -n mysqltest delete --wait=false pod/ystack-mariadb-galera-0
kubectl -n mysqltest delete --wait=false pod/ystack-mariadb-galera-2
kubectl -n mysqltest delete --wait=false pod/ystack-mariadb-galera-1
sleep 1
show_cluster_size
kubectl -n mysqltest wait --for=condition=Ready --timeout=60s pod/ystack-mariadb-galera-1
show_cluster_size

echo "From zero we expect \"base\" to fail to start"

kubectl -n mysqltest scale --replicas=0 statefulset/ystack-mariadb-galera
kubectl -n mysqltest rollout status statefulset/ystack-mariadb-galera
kubectl -n mysqltest apply -k ./base
kubectl -n mysqltest rollout status statefulset/ystack-mariadb-galera

k3d cluster delete mysqltest
