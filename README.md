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

## Tradeoffs

Testing this is a TODO.

The database should remain available during cluster upgrades and node replacement, i.e. when something like 1 out of 3 VMs is gone. A Kubernetes upgrade on GKE means 1 at a time is gone, with only a short period of time between one upgrade completes and the next starts.

Failure on 2 VMs concurrently probably mean our cluster is going down badly, and that SQL downtime isn't our major headache. In this case we expect the DB to recover automatically once 2 out of 3 nodes are live.

With 3 nodes we aim for the following characteristics, prioritizing consistency over performance:
 * Consistent reads if 1 or even 2 nodes are gone.
 * Block writes if 2 nodes are gone.
 * Ideally accept writes if 1 nodes are gone.

### Bootstrapping

Start `mysqld` with [--wsrep-new-cluster](https://mariadb.com/kb/en/library/getting-started-with-mariadb-galera-cluster/#bootstrapping-a-new-cluster) when both of these conditions are met:
 * It's the first replica, i.e. pod index from StatefulSet is `0`.
 * The data volume is empty, at the time of running the init container.

### Adding a node

We're fine with manual `replicas` change, i.e. before `kubectl apply` we'll also edit
[wsrep_cluster_address](https://mariadb.com/kb/en/library/getting-started-with-mariadb-galera-cluster/#adding-another-node-to-a-cluster).

### Restarting the cluster

If all pods have been down, we must do
[pc.bootstrap=true](https://mariadb.com/kb/en/library/getting-started-with-mariadb-galera-cluster/#restarting-the-cluster) if the following conditions are met:
 * It's the first replica, i.e. pod index from StatefulSet is `0`.
 * There _is_ state in the data volume, i.e. we have a cluster [UUID](https://mariadb.com/kb/en/library/getting-started-with-mariadb-galera-cluster/#bootstrapping-a-new-cluster).

And [pc.wait_prim=no](https://mariadb.com/kb/en/library/getting-started-with-mariadb-galera-cluster/#restarting-the-cluster) on the following:
 * Not the first replica.
 * TODO what's the difference here between first cluster start and cluster _re_start?

### Readiness

Maybe we should consider an instance ready only if it finds a peer.
Could use [SQL](https://github.com/ausov/k8s-mariadb-cluster/blob/stable-10.1/example/galera.yaml#L71) but with [wsrep status](https://mariadb.com/kb/en/library/getting-started-with-mariadb-galera-cluster/#monitoring).

### Liveness

Haven't looked for examples yet. Just check if the instance is up and running.

### Metrics

For Prometheus... TODO.

## Preparations

Unless your Kubernetes setup has volume provisioning for StatefulSet (GKE has) you need to make sure the [Persistent Volumes](http://kubernetes.io/docs/user-guide/persistent-volumes/) exist first.

Then:
 * Create namespace.
 * Create `10pvc.yml` if you created PVs manually.
 * Create configmap (see `40configmap.sh`) and secret (see `41secret.sh`).
 * Create StatefulSet's "headless" service `20mariadb-service.yml`.
 * Create the service that other applications depend on `30mysql-service.yml`.

After that start bootstrapping.

### Cluster health

Readiness and liveness probes will only assert client-level health of individual pods.
Watch logs for "sst" or "Quorum results", or run this quick check:
```
for i in 0 1 2; do kubectl -n mysql exec mariadb-$i -- mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size';" -N; done
```

### phpMyAdmin

Carefully consider the security implications before you create this. Note that it uses a non-official image.

```
kubectl create -f myadmin/
```

PhpMyAdmin has a login page where you need a mysql user. The default for root is localhost-only access (the merits of this in a micorservices context can be discussed). To allow root login from phpMyAdmin:

```
# enter pod
kubectl exec -ti mariadb-0 -- /bin/bash
# inside pod
mysql --password=$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD' WITH GRANT OPTION;
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
