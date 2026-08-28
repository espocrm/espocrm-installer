#!/usr/bin/env bash

set -euo pipefail

# Install required libs
sudo apt-get update

if ! [ -x "$(command -v curl)" ]; then
    sudo apt-get install -y --no-install-recommends \
        curl
fi

if ! [ -x "$(command -v unzip)" ]; then
    sudo apt-get install -y --no-install-recommends \
        unzip
fi

if ! [ -x "$(command -v openssl)" ]; then
    sudo apt-get install -y --no-install-recommends \
        openssl
fi

if ! [ -x "$(command -v crontab)" ]; then
    sudo apt-get install -y --no-install-recommends \
        cron
fi

# check and disable a docker snap
if [ -x "$(command -v docker)" ]; then
    if grep -q "/snap/" "$(command -v docker)"; then
        sudo snap disable docker
    fi
fi

# install docker
if ! [ -x "$(command -v docker)" ]; then
    # Use official docker installation script
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
fi
