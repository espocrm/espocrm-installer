#!/bin/bash

set -euo pipefail

if ! [ $(id -u) = 0 ]; then
   printf "Error: This script must be run as root.\n"
   exit 1
fi

# Install required libs
apt-get update

if ! [ -x "$(command -v curl)" ]; then
    apt-get install -y --no-install-recommends \
        curl
fi

if ! [ -x "$(command -v unzip)" ]; then
    apt-get install -y --no-install-recommends \
        unzip
fi

if ! [ -x "$(command -v openssl)" ]; then
    apt-get install -y --no-install-recommends \
        openssl
fi

# docker
if ! [ -x "$(command -v docker)" ]; then
    # Use official docker installation script
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
fi
