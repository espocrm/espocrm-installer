#!/bin/bash

if ! [ $(id -u) = 0 ]; then
    printf "ERROR: This script should be run as root or with sudo.\n"
    exit 1
fi

espocrmDirectory="$(dirname "$(readlink -f "$BASH_SOURCE")")"

if [ -n "$1" ]; then
    bash "$espocrmDirectory/stop.sh" "$1"
    bash "$espocrmDirectory/start.sh" "$1"
    exit 0
fi

bash "$espocrmDirectory/stop.sh"
bash "$espocrmDirectory/start.sh"
