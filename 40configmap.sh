#!/bin/bash
DIR=`dirname "$BASH_SOURCE"`

kubectl create configmap "conf-d" --from-file="$DIR/conf-d/" --namespace=mysql
