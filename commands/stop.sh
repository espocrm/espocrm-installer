#!/bin/bash

if ! [ $(id -u) = 0 ]; then
    printf "ERROR: This script should be run as root or with sudo.\n"
    exit 1
fi

if [ -n "$1" ]; then
    docker stop "$1"
    docker rm "$1"
    exit 0
fi

docker stop $(docker ps -aqf "name=espocrm")
docker rm $(docker ps -aqf "name=espocrm")

printf "Stopped.\n"
