#!/bin/bash
DIR=`dirname "$BASH_SOURCE"`
set -e
set -x

cp "$DIR/50mariadb.yml" "$DIR/50mariadb.yml.unbootstrap.yml"

sed -i '' 's/replicas: 1/replicas: 3/' "$DIR/50mariadb.yml.unbootstrap.yml"
sed -i '' 's/- --wsrep-new-cluster/#- --wsrep-new-cluster/' "$DIR/50mariadb.yml.unbootstrap.yml"

kubectl apply -f "$DIR/50mariadb.yml.unbootstrap.yml"
rm "$DIR/50mariadb.yml.unbootstrap.yml"
