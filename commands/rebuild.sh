#!/bin/bash

if ! [ $(id -u) = 0 ]; then
    printf "ERROR: This script should be run as root or with sudo.\n"
    exit 1
fi

espocrmDirectory="$(dirname "$(readlink -f "$BASH_SOURCE")")"

bash "$espocrmDirectory/restart.sh" espocrm

/usr/bin/docker exec --user www-data -i espocrm /bin/bash -c "php command.php rebuild"
