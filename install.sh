#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
sudo apt install dnsutils iputils-ping -yq

if [[ $# -eq 0 ]] ; then
    echo 'Domain not present'
    exit 1
fi

DOMAIN=$1

MY_IP=$(curl http://checkip.amazonaws.com)
DOMAIN_IP=$(dig +short $DOMAIN | head -1)

if [[ "$MY_IP" != "$DOMAIN_IP" ]] ; then
    echo "Domain not resolve A record to ip $MY_IP"
    exit 1
fi

sudo apt install -y lsb-release wget apt-transport-https
sudo wget -O /usr/share/keyrings/matrix-org-archive-keyring.gpg https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ $(lsb_release -cs) main" |
    sudo tee /etc/apt/sources.list.d/matrix-org.list
sudo apt update -y
sudo apt install -y nginx cron socat

curl https://get.acme.sh | sh
export LE_WORKING_DIR="/root/.acme.sh"
alias acme.sh="/root/.acme.sh/acme.sh"
shopt -s expand_aliases
acme.sh  --register-account  -m test@gmail.com --server zerossl

sudo iptables -S INPUT -p tcp -m tcp --dport 80 -j ACCEPT || sudo iptables -I INPUT -p tcp -m tcp --dport 80 -j ACCEPT
sudo iptables -S INPUT -p tcp -m tcp --dport 443 -j ACCEPT || sudo iptables -I INPUT -p tcp -m tcp --dport 443 -j ACCEPT
sudo /sbin/iptables-save

acme.sh --issue -d $DOMAIN --webroot /var/www/html
mkdir -p /etc/mtrxcerts/
acme.sh --install-cert -d $DOMAIN --key-file /etc/mtrxcerts/key.pem --fullchain-file /etc/mtrxcerts/fullchain.pem --reloadcmd "systemctl reload nginx.service"

sudo apt install -y wget apt-transport-https
sudo wget -O /usr/share/keyrings/element-io-archive-keyring.gpg https://packages.element.io/debian/element-io-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/element-io-archive-keyring.gpg] https://packages.element.io/debian/ default main" | sudo tee /etc/apt/sources.list.d/element-io.list
sudo apt update
sudo apt install -y matrix-synapse-py3 libpq5 element-desktop