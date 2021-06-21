#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -eo pipefail
DIR="$(dirname $0)"

export KUBECONFIG=$DIR/kubeconfig

show_cluster_size() {
  kubectl -n mysqltest exec -c mariadb-galera ystack-mariadb-galera-0 -- mysql -u root "-pTESTROOT" -N -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 
}

k3d cluster create mysqltest --agents 3 --agents-memory 512M

# https://github.com/Yolean/ystack/blob/master/bin/y-cluster-assert-install
ctx=""
OPERATOR_VERSION=5555f492df250168657b72bb8cb60bec071de71f
KUBERNETES_ASSERT_VERSION=cb66d46758654b819d0d4402857122dca1884bcb
kubectl $ctx create namespace monitoring
kubectl $ctx -n default apply -f https://github.com/prometheus-operator/prometheus-operator/raw/$OPERATOR_VERSION/bundle.yaml
kubectl wait $ctx -n default --for=condition=Ready pod -l app.kubernetes.io/name=prometheus-operator
kubectl $ctx -n monitoring apply -k github.com/Yolean/kubernetes-assert/example-small?ref=$KUBERNETES_ASSERT_VERSION
kubectl wait $ctx -n monitoring --for=condition=Ready pod --all

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

echo "# From zero we expect \"base\" to fail to start"

kubectl -n mysqltest scale --replicas=0 statefulset/ystack-mariadb-galera
kubectl -n mysqltest rollout status statefulset/ystack-mariadb-galera
kubectl -n mysqltest apply -k ./base
kubectl -n mysqltest rollout status --timeout=30s statefulset/ystack-mariadb-galera || echo "Timeout is expected"
kubectl -n mysqltest get pods
echo "# Prometheus will now report absent(mysql_global_status_wsrep_cluster_size) == 1"

kubectl -n mysqltest apply -k ./base-bootstrap
sleep 5
kubectl -n mysqltest get pods
kubectl -n mysqltest logs -c mariadb-galera ystack-mariadb-galera-0

echo "# Using bootstrap-force, assuming that pod 0 has the latest writes"
echo "# To bootstrap from a different node use the helm chart"
kubectl -n mysqltest apply -k ./base-bootstrap-force
kubectl -n mysqltest rollout status statefulset/ystack-mariadb-galera
show_cluster_size

echo "# Upon bootstrap success, apply the regular base to prevent more bootstrapping"
kubectl -n mysqltest apply -k ./base
kubectl -n mysqltest rollout status statefulset/ystack-mariadb-galera
show_cluster_size

k3d cluster delete mysqltest
