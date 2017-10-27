#!/bin/bash
DIR=`dirname "$BASH_SOURCE"`

kubectl create secret generic "conf-d" --from-file="$DIR/conf-d/" --namespace=mysql
