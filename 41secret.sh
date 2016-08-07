#!/bin/bash
echo -n Please enter mysql root password for upload to k8s secret:
read -s rootpw
echo
kubectl create secret generic mysql-secret --namespace=mysql --from-literal=rootpw=$rootpw
