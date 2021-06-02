#!/bin/bash

set -euo pipefail

if ! [ $(id -u) = 0 ]; then
   printf "Error: this script must be run as root\n"
   exit 1
fi

source installation-modes/utils.sh

cp ./installation-modes/http/nginx/espocrm.conf ./installation-modes/ssl/nginx/espocrm.conf

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

handleParams "$@"

prepareConfiguration

mkdir -p ./nginx/ssl/live/$domain
touch ./nginx/ssl/live/$domain/PUT_HERE_YOUR_CERTIFICATES

# Generate dummy certificates
openssl req -x509 -nodes -days 30 -subj "/CN=$domain" -newkey rsa:4096 -keyout ./nginx/ssl/live/$domain/privkey.pem -out ./nginx/ssl/live/$domain/fullchain.pem;

createDockerNetwork "external"
