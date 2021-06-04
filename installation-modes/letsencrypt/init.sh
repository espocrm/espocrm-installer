#!/bin/bash

set -euo pipefail

if ! [ $(id -u) = 0 ]; then
   printf "Error: this script must be run as root\n"
   exit 1
fi

source installation-modes/utils.sh

cp ./installation-modes/http/nginx/espocrm.conf ./installation-modes/letsencrypt/nginx/espocrm.conf

scriptDirectory="$(dirname "$(readlink -f "$BASH_SOURCE")")"
cd "$scriptDirectory"

handleParams "$@"

prepareConfiguration

# Let's Encrypt

mkdir -p ./ssl \
    ./tmp \
    ./certbot

curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "ssl/ssl-options.conf"
curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "ssl/dhparams.pem"

# Run templorary nginx
echo "server {
    listen 80;
    listen [::]:80;

    server_name $domain;

    location ~ /.well-known/acme-challenge {
        allow all;
        root /var/www/certbot;
    }
}" > ./tmp/nginx-default.conf

# Check and remove existing tmp-nginx
docker container inspect tmp-nginx > /dev/null 2>&1 && docker rm -f tmp-nginx

# Run tmp-nginx
docker run --name tmp-nginx \
    -v $scriptDirectory/tmp/nginx-default.conf:/etc/nginx/conf.d/default.conf \
    -v $scriptDirectory/ssl:/etc/letsencrypt \
    -v $scriptDirectory/certbot:/var/www/certbot \
    -p 80:80 \
    -d nginx

# Generate certificates
docker run -it --rm \
    -v $scriptDirectory/ssl:/etc/letsencrypt \
    -v $scriptDirectory/certbot:/var/www/certbot \
    certbot/certbot \
    certonly --webroot \
    -w /var/www/certbot \
    --agree-tos \
    --no-eff-email \
    --email $email \
    --rsa-key-size 4096 \
    --force-renewal \
    --staging \
    -d $domain

docker stop tmp-nginx
docker rm tmp-nginx
rm -rf ./tmp

if [ ! -d "./ssl/live/$domain" ]; then
    echo "Error: Failed to create Let's Encrypt certificate. Please fix errors described above and try again."
    exit 1
fi

createDockerNetwork "external"
