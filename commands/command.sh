#!/bin/bash

if ! [ $(id -u) = 0 ]; then
    printf "ERROR: This script should be run as root or with sudo.\n"
    exit 1
fi

function actionHelp() {
    printf "Available commands:\n"

    printf "  status      Status of services\n"
    printf "  restart     Restart services\n"
    printf "  start       Start services\n"
    printf "  stop        Stop services\n"
    printf "  rebuild     Run EspoCRM rebuild\n"
    printf "  help        Information about the commands\n"
}

function actionRebuild() {
    /usr/bin/docker exec --user www-data -i espocrm /bin/bash -c "php command.php rebuild"
}

function actionRestart() {
    if [ -n "$1" ]; then
        actionStop "$1"
        actionStart "$1"
        return
    fi

    actionStop
    actionStart
}

function actionStart() {
    if [ -n "$1" ]; then
        docker-compose -f "$espocrmDirectory/docker-compose.yml" up -d "$1"
        return
    fi

    docker-compose -f "$espocrmDirectory/docker-compose.yml" up -d
}

function actionStatus() {
    docker ps -f "name=espocrm"
}

function actionStop() {
    if [ -n "$1" ]; then
        docker stop "$1"
        docker rm "$1"
        return
    fi

    docker stop $(docker ps -aqf "name=espocrm")
    docker rm $(docker ps -aqf "name=espocrm")

    printf "Stopped.\n"
}

espocrmDirectory="$(dirname "$(readlink -f "$BASH_SOURCE")")"

action=${1:-help}
option=${2:-}

case "$action" in
    help)
        actionHelp
        ;;

    rebuild)
        actionRebuild
        ;;

    restart)
        actionRestart "$option"
        ;;

    start)
        actionStart "$option"
        ;;

    status)
        actionStatus
        ;;

    stop)
        actionStop "$option"
        ;;
esac