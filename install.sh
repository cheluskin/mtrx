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
sudo apt install -y nginx cron socat haveged

curl https://get.acme.sh | sh
export LE_WORKING_DIR="/root/.acme.sh"
alias acme.sh="/root/.acme.sh/acme.sh"
shopt -s expand_aliases
acme.sh  --register-account  -m test@gmail.com --server zerossl

sudo iptables -I INPUT -p tcp -m tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT -p tcp -m tcp --dport 443 -j ACCEPT
sudo /sbin/iptables-save > /etc/iptables/rules.v4

acme.sh --issue -d $DOMAIN --force --webroot /var/www/html
mkdir -p /etc/mtrxcerts/
acme.sh --install-cert -d $DOMAIN --key-file /etc/mtrxcerts/key.pem --fullchain-file /etc/mtrxcerts/fullchain.pem --reloadcmd "systemctl reload nginx.service"

mkdir -p /etc/nginx/dhparams 
openssl dhparam -dsaparam -out /etc/nginx/dhparams/dhparams.pem 4096

sudo apt install -y wget apt-transport-https
sudo wget -O /usr/share/keyrings/element-io-archive-keyring.gpg https://packages.element.io/debian/element-io-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/element-io-archive-keyring.gpg] https://packages.element.io/debian/ default main" | sudo tee /etc/apt/sources.list.d/element-io.list
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq matrix-synapse-py3 libpq5
cd /var/www/html
sudo wget https://github.com/vector-im/element-web/releases/download/v1.10.14-rc.1/element-v1.10.14-rc.1.tar.gz
sudo tar -xzvf element-v1.10.14-rc.1.tar.gz
cd element-v1.10.14-rc.1
cp -rf * ..
rm -rf *
cd ..
rm -rf rm -rf element-v1.10.14-rc.1
rm -f element-v1.10.14-rc.1.tar.gz

cat > /var/www/html/config.json <<EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://$DOMAIN",
            "server_name": "$DOMAIN"
        },
        "m.identity_server": {}
    },
    "disable_custom_urls": false,
    "disable_guests": true,
    "disable_login_language_selector": false,
    "disable_3pid_login": false,
    "brand": "Element",
    "integrations_ui_url": "https://scalar.vector.im/",
    "integrations_rest_url": "https://scalar.vector.im/api",
    "integrations_widgets_urls": [
        "https://scalar.vector.im/_matrix/integrations/v1",
        "https://scalar.vector.im/api",
        "https://scalar-staging.vector.im/_matrix/integrations/v1",
        "https://scalar-staging.vector.im/api",
        "https://scalar-staging.riot.im/scalar/api"
    ],
    "bug_report_endpoint_url": "https://element.io/bugreports/submit",
    "uisi_autorageshake_app": "element-auto-uisi",
    "default_country_code": "RU",
    "show_labs_settings": false,
    "features": { },
    "default_federate": false,
    "default_theme": "dark",
    "room_directory": {
        "servers": [
            "$DOMAIN"
        ]
    },
    "enable_presence_by_hs_url": {
        "https://matrix.org": false,
        "https://matrix-client.matrix.org": false
    },
    "setting_defaults": {
        "breadcrumbs": true
    },
    "jitsi": {
        "preferred_domain": "meet.element.io"
    },
    "map_style_url": "https://api.maptiler.com/maps/streets/style.json?key=fU3vlMsMn4Jb6dnEIFsx",
    "permalinkPrefix": "https://$DOMAIN"
}
EOF

cat > /etc/nginx/conf.d/mtrx.conf <<EOF
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    server_name $DOMAIN;

    ssl_certificate /etc/mtrxcerts/fullchain.pem;
    ssl_certificate_key /etc/mtrxcerts/key.pem;

    ssl_session_cache shared:SSL:20m;
    ssl_session_timeout 60m;
    
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_dhparam /etc/nginx/dhparams/dhparams.pem;

    ssl_ciphers EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH;
    ssl_prefer_server_ciphers on;
    server_tokens off;
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/mtrxcerts/fullchain.pem;

    location / {
        add_header X-Frame-Options SAMEORIGIN;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Content-Security-Policy "frame-ancestors 'none'";
        root /var/www/html;
        index index.html;

    }

    location ~ ^(/_matrix|/_synapse/client) {
        proxy_pass http://localhost:8008;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;
        client_max_body_size 50M;
    }
}
EOF

SECRET=$(openssl rand -hex 18)

cat > /etc/matrix-synapse/conf.d/mtrx.yaml <<EOF
database:
  name: psycopg2
  args:
    user: synapse_user
    password: synapse_password
    database: synapse
    host: localhost

federation_domain_whitelist: []
allow_public_rooms_without_auth: false
allow_public_rooms_over_federation: false
registration_shared_secret: "$SECRET"

EOF

cat > /etc/matrix-synapse/conf.d/server_name.yaml <<EOF
server_name: $DOMAIN

EOF

sudo apt install -yq postgresql postgresql-contrib
sudo systemctl restart postgresql
sudo -Hiu postgres bash -c "psql -c \"DROP database IF EXISTS synapse;\""
sudo -Hiu postgres bash -c "psql -c \"DROP USER IF EXISTS synapse_user;\""
sudo -Hiu postgres bash -c "psql -c \"CREATE USER synapse_user WITH PASSWORD 'synapse_password';\""
sudo -Hiu postgres bash -c "psql -c \"CREATE DATABASE synapse WITH OWNER synapse_user LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0 ENCODING 'UTF8';\""
PGHBAPATH=$(sudo -Hiu postgres bash -c "psql -t -P format=unaligned -c 'show hba_file';")
cat > $PGHBAPATH <<EOF
local   all             all                                     trust
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
EOF

sudo systemctl restart postgresql
sudo systemctl restart matrix-synapse
sudo systemctl restart nginx

PASSWORD=$(openssl rand -hex 12)

/usr/bin/register_new_matrix_user -u root -p $PASSWORD -a -c /etc/matrix-synapse/conf.d/mtrx.yaml http://localhost:8008
echo user root
echo password $PASSWORD
echo \n
echo /usr/bin/register_new_matrix_user -u username -p userpassword -c /etc/matrix-synapse/conf.d/mtrx.yaml http://localhost:8008






