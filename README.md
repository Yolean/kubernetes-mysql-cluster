# MySQL with automatic failover on Kubernetes

Our requirement was an SQL server for modest loads
but with high availability because it backs our login system
and public web.

We want automatic failover, not manual, and a single configuration to maintain, not leaders and followers.

Initially we tried Postgres, but clustering solutions like [pgpool-II]() felt a bit outdated, and [patroni](https://github.com/zalando/patroni) etc was overly complex for our needs.

[Galera](http://galeracluster.com/) is a good fit for us with Kubernetes because it allows nodes to share the same configuration through `wsrep_cluster_address="gcomm://host-0,host-1`... where access to only 1 of those instances lets a new instance join the cluster.

As of [MariaDB](https://mariadb.com/) [10.1](https://mariadb.com/kb/en/mariadb/what-is-mariadb-galera-cluster/) the [official docker image](https://hub.docker.com/_/mariadb/) comes with "wsrep" support. Using official images direcly mean less maintenance for us.

Using a semi-manual bootstrap process and a container with galera support built in, we were able to simplify the setup and thus the maintenance.

# What's new since our initial setup?

 * https://github.com/ausov/k8s-mariadb-cluster
 * [https://github.com/kubernetes/website/blob/master/docs/tasks/run-application/run-replicated-stateful-application.md](https://kubernetes.io/docs/tasks/run-application/run-replicated-stateful-application/)
 * https://github.com/openstack/kolla-kubernetes/blob/master/helm/service/mariadb/requirements.yaml

## Tradeoffs

Testing this is a TODO.

The database should remain available during cluster upgrades and node replacement, i.e. when something like 1 out of 3 VMs is gone. A Kubernetes upgrade on GKE means 1 at a time is gone, with only a short period of time between one upgrade completes and the next starts.

Failure on 2 VMs concurrently probably mean our cluster is going down badly, and that SQL downtime isn't our major headache. In this case we expect the DB to recover automatically once 2 out of 3 nodes are live.

With 3 nodes we aim for the following characteristics, prioritizing consistency over performance:
 * Consistent reads if 1 or even 2 nodes are gone.
 * Block writes if 2 nodes are gone.
 * Ideally accept writes if 1 nodes are gone.

## Preparations

Unless your Kubernetes setup has volume provisioning for StatefulSet (GKE has) you need to make sure the [Persistent Volumes](http://kubernetes.io/docs/user-guide/persistent-volumes/) exist first.

Then:
 * Create namespace.
 * Create `10pvc.yml` if you created PVs manually.
 * Create configmap (see `40configmap.sh`) and secret (see `41secret.sh`).
 * Create StatefulSet's "headless" service `20mariadb-service.yml`.
 * Create the service that other applications depend on `30mysql-service.yml`.

After that start bootstrapping.

### Initialize volumes and cluster

First get a single instance with `--wsrep-new-cluster` up and running:

```
kubectl create -f ./
kubectl logs -f mariadb-0
```

You should see something like

```
...[Note] WSREP: Quorum results:
  version    = 3,
  component  = PRIMARY,
  conf_id    = 0,
  members    = 1/1 (joined/total),
  act_id     = 4,
  last_appl. = -1,
  protocols  = 0/7/3 (gcs/repl/appl),
```

Now keep that pod running, but change StatefulSet to create normal replicas.

```
./70unbootstrap.sh
```

This scales to three nodes. You can `kubectl -n mysql logs -f mariadb-1` to see something like:

```
[Note] WSREP: Quorum results:
	version    = 3,
	component  = PRIMARY,
	conf_id    = 4,
	members    = 2/3 (joined/total),
	act_id     = 4,
	last_appl. = 0,
	protocols  = 0/7/3 (gcs/repl/appl),
```

Now you can ```kubectl -n mysql delete pod mariadb-0``` and it'll be re-created without the `--wsrep-new-cluster` argument. Logs will confirm that the new `mariadb-0` joins the cluster.

Keep at least 1 node running at all times - which is what you want anyway,
and the manual "unbootstrap" step isn't a big deal.

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
