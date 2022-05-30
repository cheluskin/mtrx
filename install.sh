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

sudo apt install -y lsb-release wget apt-transport-https
sudo wget -O /usr/share/keyrings/matrix-org-archive-keyring.gpg https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ $(lsb_release -cs) main" |
    sudo tee /etc/apt/sources.list.d/matrix-org.list
sudo apt update -y
sudo apt install -y matrix-synapse-py3 libpq5 nginx

curl https://get.acme.sh | sh
acme.sh  --register-account  -m test@gmail.com --server zerossl
acme.sh --issue --standalone -d $DOMAIN
mkdir -p /etc/mtrxcerts/
acme.sh --install-cert -d $DOMAIN --key-file /etc/mtrxcerts/key.pem --fullchain-file /etc/mtrxcerts/fullchain.pem --reloadcmd "systemctl reload nginx.service"



