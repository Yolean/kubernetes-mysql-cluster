# MySQL with automatic failover on Kubernetes

Our requirement was an SQL server for modest loads
but with high availability because it backs our login system
and public web.

We want automatic failover, not manual, and a single configuration to maintain, not leaders and followers.

Initially we tried Postgres, but clustering solutions like [pgpool-II]() felt a bit outdated, and [patroni](https://github.com/zalando/patroni) etc was overly complex for our needs.

[Galera](http://galeracluster.com/) is a good fit for us with Kubernetes because it allows nodes to share the same configuration through `wsrep_cluster_address="gcomm://host-0,host-1`... where access to only 1 of those instances lets a new instance join the cluster.

As of [MariaDB](https://mariadb.com/) [10.1](https://mariadb.com/kb/en/mariadb/what-is-mariadb-galera-cluster/) the [official docker image](https://hub.docker.com/_/mariadb/) comes with "wsrep" support. Using official images direcly mean less maintenance for us.

Kubernetes [recently added](http://blog.kubernetes.io/2016/07/kubernetes-1.3-bridging-cloud-native-and-enterprise-workloads.html) support for "stateful applications", the [PetSet](http://kubernetes.io/docs/user-guide/petset/). There's a [semi-official](https://github.com/kubernetes/contrib/tree/master/pets/mysql) example using MySQL.
It's more an example of what you can do with PetSet than a production setup.
It uses the init container concept, which looks heavily alpha, to try to automate installation.

Using a semi-manual bootstrap process and a container with galera support built in, we were able to simplify the setup and thus the maintenance.

## Tradeoffs

Testing this is a TODO.

The database should remain available during cluster upgrades and node replacement, i.e. when something like 1 out of 3 VMs is gone. A Kubernetes upgrade on GKE means 1 at a time is gone, with only a short period of time between one upgrade completes and the next starts.

Failure on 2 VMs concurrently probably mean our cluster is going down badly, and that SQL downtime isn't our major headache. In this case we expect the DB to recover automatically once 2 out of 3 nodes are live.

With 3 nodes we aim for the following characteristics, prioritizing consistency over performance:
 * Consistent reads if 1 or even 2 nodes are gone.
 * Block writes if 2 nodes are gone.
 * Ideally accept writes if 1 nodes are gone.

## Preparations

Unless your Kubernetes setup has volume provisioning for PetSet (GKE has) you need to make sure the [Persistent Volumes](http://kubernetes.io/docs/user-guide/persistent-volumes/) exist first.

Then:
 * Create namespace.
 * Create `10pvc.yml` if you created PVs manually.
 * Create configmap (see `40configmap.sh`) and secret (see `41secret.sh`).
 * Create petset's "headless" service `20mariadb-service.yml`.
 * Create the service that other applications depend on `30mysql-service.yml`.

After that start bootstrapping.

### Initialize volumes and cluster

Bootstrapping uses a slightly modified copy of the PetSet definition, with a single replica and an added argument `--wsrep-new-cluster`. So don't `kubectl create` from `./50mariadb.yml` unless you already have a cluster running. Instead:

```
kubectl create -f bootstrap/50mariadb.yml
# wait for Running state, then
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

Now keep that pod running, but change PetSet to create normal replicas.

```
kubectl delete -f bootstrap/50mariadb.yml
kubectl create -f 50mariadb.yml
# wait again, then
kubectl logs -f mariadb-1
```

You might get a restart, but then something like

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

Now you can delete `mariadb-0` and it'll be re-created for you
without the `--wsrep-new-cluster` argument.

Keep at least 1 node running at all times,
and the manual cluster setup wasn't a big deal.

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

### Healthz

This is a TODO. The healthz folder is a copy of https://github.com/kubernetes/contrib/tree/master/pets/mysql/healthz.

### Storage

Why we request only 100 Mb storage? We aim to learn to monitor our volumes and [resize](https://cloud.google.com/sdk/gcloud/reference/compute/disks/resize) on demand. For hostPath volumes the size doesn't matter, as long as PV and PVC sizes match.
