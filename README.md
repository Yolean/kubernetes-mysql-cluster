# MySQL with automatic failover on Kubernetes

RETIRED See [v2.1.0](https://github.com/Yolean/kubernetes-mysql-cluster/tree/v2.1.0) for the original setup.

We've now adopted the
[Bitnami mariadb-galera helm chart](https://github.com/bitnami/charts/tree/master/bitnami/mariadb-galera)
via [unhelm](https://github.com/Yolean/unhelm/tree/master/mysql) so we can use [Kustomize](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#kustomize).
