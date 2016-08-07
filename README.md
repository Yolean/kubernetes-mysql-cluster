# MySQL with automatic failover on Kubernetes



### Initialize volumes and cluster

For bootstrapping the cluster we might use init containers,
but note the complexity in https://github.com/kubernetes/contrib/tree/master/pets/mysql.
You only need to do this once, so semi-manual is ok.
```
# before you create ./50mariadb.yml for the first time
kubectl create -f bootstrap/50mariadb.yml
# inspect bootstrapping, then
kubectl delete -f bootstrap/50mariadb.yml
kubectl create -f 50mariadb.yml
# For phpMyAdmin. Insecure.
kubectl exec mariadb-0 -- mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '[rootpw]' WITH GRANT OPTION;"
```

### Healthz

This is a TODO. The healthz folder is a copy of https://github.com/kubernetes/contrib/tree/master/pets/mysql/healthz.
