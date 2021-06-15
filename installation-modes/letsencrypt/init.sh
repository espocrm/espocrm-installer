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

mkdir -p "./$server/ssl" \
    "./$server/certbot" \
    ./tmp

curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "./$server/ssl/ssl-options.conf"
curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "./$server/ssl/dhparams.pem"

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

# Check and remove existing espocrm-nginx-tmp
docker container inspect espocrm-nginx > /dev/null 2>&1 && docker rm -f espocrm-nginx
docker container inspect espocrm-nginx-tmp > /dev/null 2>&1 && docker rm -f espocrm-nginx-tmp

# Run espocrm-nginx-tmp
docker run --name espocrm-nginx-tmp \
    -v "$scriptDirectory/tmp/nginx-default.conf":/etc/nginx/conf.d/default.conf \
    -v "$scriptDirectory/$server/ssl":/etc/letsencrypt \
    -v "$scriptDirectory/$server/certbot":/var/www/certbot \
    -p 80:80 \
    -d nginx

# Generate certificates
docker run -it --rm \
    -v "$scriptDirectory/$server/ssl":/etc/letsencrypt \
    -v "$scriptDirectory/$server/certbot":/var/www/certbot \
    certbot/certbot \
    certonly --webroot \
    -w /var/www/certbot \
    --agree-tos \
    --no-eff-email \
    --email $email \
    --rsa-key-size 4096 \
    --force-renewal \
    -d $domain

docker stop espocrm-nginx-tmp > /dev/null 2>&1
docker rm espocrm-nginx-tmp > /dev/null 2>&1

rm -rf ./tmp

if [ ! -d "./$server/ssl/live/$domain" ]; then
    echo "Error: Failed to create Let's Encrypt certificate. Please fix errors described above and try again."
    exit 1
fi

createDockerNetwork "external"
