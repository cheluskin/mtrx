#!/bin/bash
set -e

if [[ $# -eq 0 ]] ; then
    echo 'Domain not present'
    exit 1
fi

DOMAIN=$1

MY_IP=$(curl http://checkip.amazonaws.com)
DOMAIN_IP=$(dig +short $DOMAIN | head -1)

if [[ "$MY_IP" != "$DOMAIN_IP" ]] ; then
    echo "Domain not resolve A record to ip $my_ip"
    exit 1
fi
