#!/usr/bin/env bash

set -euo pipefail

if ! [ -x "$(command -v brew)" ]; then
   printf "Error: The berw package manager must be installed.\n"
   exit 1
fi

if ! [ -x "$(command -v crontab)" ]; then
   printf "Error: crontab not found (should exist on macOS).\n"
   exit 1
fi

brew update

if ! [ -x "$(command -v curl)" ]; then
    brew install curl
fi

if ! [ -x "$(command -v unzip)" ]; then
    brew install unzip
fi

if ! [ -x "$(command -v openssl)" ]; then
    brew install openssl
fi

if ! [ -x "$(command -v docker)" ]; then
    brew install --cask docker
fi