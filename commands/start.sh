#!/bin/bash

if ! [ $(id -u) = 0 ]; then
    printf "ERROR: This script should be run as root or with sudo.\n"
    exit 1
fi

espocrmDirectory="$(dirname "$(readlink -f "$BASH_SOURCE")")"

if [ -n "$1" ]; then
    docker-compose -f "$espocrmDirectory/docker-compose.yml" up -d "$1"
    exit 0
fi

docker-compose -f "$espocrmDirectory/docker-compose.yml" up -d
