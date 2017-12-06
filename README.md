# MySQL with automatic failover on Kubernetes

Our requirement was an SQL server for modest loads
but with high availability because it backs our login system
and public web.

We want automatic failover, not manual, and a single configuration to maintain, not leaders and followers.

Initially we tried Postgres, but clustering solutions like [pgpool-II]() felt a bit outdated, and [patroni](https://github.com/zalando/patroni) etc was overly complex for our needs.

[Galera](http://galeracluster.com/) is a good fit for us with Kubernetes because it allows nodes to share the same configuration through `wsrep_cluster_address="gcomm://host-0,host-1`... where access to only 1 of those instances lets a new instance join the cluster.

As of [MariaDB](https://mariadb.com/) [10.1](https://mariadb.com/kb/en/mariadb/what-is-mariadb-galera-cluster/) the [official docker image](https://hub.docker.com/_/mariadb/) comes with "wsrep" support. Using official images direcly mean less maintenance for us.
We'll use an init container, instead of a custom image with modified entrypoint.

Using a semi-manual bootstrap process and a container with galera support built in, we were able to simplify the setup and thus the maintenance.

## What's new since our initial setup?

 * https://github.com/ausov/k8s-mariadb-cluster
 * [https://github.com/kubernetes/website/blob/master/docs/tasks/run-application/run-replicated-stateful-application.md](https://kubernetes.io/docs/tasks/run-application/run-replicated-stateful-application/)
 * https://github.com/openstack/kolla-kubernetes/blob/master/helm/service/mariadb/requirements.yaml
 * https://github.com/kubernetes/contrib/tree/master/peer-finder

## Preparations

Unless your Kubernetes setup has volume provisioning for StatefulSet (GKE has) you need to make sure the [Persistent Volumes](http://kubernetes.io/docs/user-guide/persistent-volumes/) exist first.

Then:
 * Create namespace.
 * Create `10pvc.yml` if you created PVs manually.
 * Create configmap (see `40configmap.sh`) and secret (see `41secret.sh`).
 * Create StatefulSet's "headless" service `20mariadb-service.yml`.
 * Create the service that other applications depend on `30mysql-service.yml`.

After that start bootstrapping.

### Cluster Health

Readiness and liveness probes will only assert client-level health of individual pods.
Watch logs for "sst" or "Quorum results", or run this quick check:
```
for i in 0 1 2; do kubectl -n mysql exec mariadb-$i -- mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size';" -N; done
```

Port 9104 exposes plaintext metris in [Prometheus](https://prometheus.io/docs/concepts/data_model/) scrape format.
```
# with kubectl -n mysql port-forward mariadb-0 9104:9104
$ curl -s http://localhost:9104/metrics | grep ^mysql_global_status_wsrep_cluster_size
mysql_global_status_wsrep_cluster_size 3
```

A reasonable alert is on `mysql_global_status_wsrep_cluster_size` staying below the desired number of replicas.

### Cluster un-health

We need to assume a couple of things here. First and foremost:
Production clusters are configured so that the statefulset pods do not go down together.

 * Pods are properly spread across nodes - which this repo can try to test.
 * Nodes are spread across multiple availability zones.

Let's also assume there is monitoring.
Any `wsrep_cluster_size` issue (see above), or absence of `wsrep_cluster_size`
should lead to a human being paged.

Rarity combined with manual attention means that this statefulset can/should avoid
attempts at automatic [recovery](http://galeracluster.com/documentation-webpages/pcrecovery.html).
The reason for that is that we can't test for failure modes properly,
as they depend on the Kubernetes setup.
Automatic attempts may appint the wrong leader, losing writes,
or cause split-brain situations.

We can however support detection in the init script.

Scaling down to two instances
-- actually one instance, but nodes should be considered ephemeral so don't do that --
and up to any number is considered normal operations.

### phpMyAdmin

Carefully consider the security implications before you create this. Note that it uses a non-official image.

```
kubectl apply -f myadmin/
```

PhpMyAdmin has a login page where you need a mysql user. To allow login (with full access) create a user with your choice of password:

```
kubectl -n mysql exec mariadb-0 -- mysql -e "CREATE USER 'phpmyadmin'@'%' IDENTIFIED BY 'my-admin-pw'; GRANT ALL ON *.* TO 'phpmyadmin'@'%';"
```

## Recover

It's in scope for this repo to support scaling down to 0 pods, then scale upp again (for example at maintenance or major upgrades). It's outside the scope of this repo to recover from crashes.

In the unlikely event that all pods crash, the statefulset tries to restart the pods but can fail with an infinite loop.

In order to restart the cluster, the "Safe-To-Bootstrap" flag must be set. Please follow the instructions found [here](http://galeracluster.com/2016/11/introducing-the-safe-to-bootstrap-feature-in-galera-cluster/)

Note that their use of the word _Node_ refers to a Pod and its volume in the Kubernetes world. So to change the `safe_to_bootstrap` flag, start a new pod with the correct volume attached.

### Summary (If link becomes broken)

Recreate 50mariadb.yml with `--wsrep-recover` command arg flag set

Get the log using `kubectl -n mysql logs -f mariadb-0` and look for the following output.

```
...
2016-11-18 01:42:15 36311 [Note] InnoDB: Database was not shutdown normally!
2016-11-18 01:42:15 36311 [Note] InnoDB: Starting crash recovery.
...
2016-11-18 01:42:16 36311 [Note] WSREP: Recovered position: 37bb872a-ad73-11e6-819f-f3b71d9c5ada:345628
...
2016-11-18 01:42:17 36311 [Note] /home/philips/git/mysql-wsrep-bugs-5.6/sql/mysqld: Shutdown complete
```

The number after the UUID string on the "Recovered position" line is the one to watch.

Pick the volume that has the highest such number and edit its `grastate.dat` to set `safe_to_bootstrap: 1`:
```
# GALERA saved state
version: 2.1
uuid:    37bb872a-ad73-11e6-819f-f3b71d9c5ada
seqno:   -1
safe_to_bootstrap: 1
```

Remove the `--wsrep-recover` and continue as *Initialize volumes and cluster*
