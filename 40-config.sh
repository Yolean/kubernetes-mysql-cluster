#!/bin/bash
set -e
set -x
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "${NAMESPACE}" ]; then
    NAMESPACE=mysql
fi

kctl() {
    kubectl --namespace "$NAMESPACE" "$@"
}

SECRET=conf-d

kctl create secret generic $SECRET --from-file="$DIR/conf-d/" || \
kctl create secret generic $SECRET --from-file="$DIR/conf-d/" \
    --dry-run -o=yaml \
    | kctl replace secret generic $SECRET -f -
