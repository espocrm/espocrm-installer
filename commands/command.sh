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
    printf "  build       Build and start services\n"
    printf "  rebuild     Run EspoCRM rebuild\n"
    printf "  upgrade     Upgrade all EspoCRM services\n"
    printf "  clean       Remove old and unused data\n"
    printf "  logs        See the EspoCRM container logs\n"
    printf "  backup      Backup all EspoCRM services\n"
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
    docker-compose -f "$espocrmDirectory/docker-compose.yml" down
}

function actionBuild() {
    docker-compose -f "$espocrmDirectory/docker-compose.yml" up -d --build "$@"
    docker-compose up --build -d
}

function actionUpgrade() {
    docker-compose -f "$espocrmDirectory/docker-compose.yml" pull
    docker-compose -f "$espocrmDirectory/docker-compose.yml" up -d
}

function actionClean() {
    docker image prune -f
}

function actionLogs() {
    docker logs espocrm
}

function actionBackup() {
    local homeDirectory="/var/www/espocrm"
    local backupPath=${1:-"/var/www/espocrm-backup"}

    backupPath=${backupPath%/}
    backupFilePath="${backupPath}/$(date +'%Y-%m-%d_%H%M%S').tar.gz"

    if [ ! -f "${homeDirectory}/docker-compose.yml" ]; then
        echo "Error: The EspoCRM is not found."
        exit 1
    fi

    echo "Creating a backup..."

    mkdir -p "${backupPath}" || {
        exit 1
    }

    tar -czf "${backupFilePath}" -C "${homeDirectory}" . --exclude="access.log"

    echo "Backup is created: ${backupFilePath}"
}

espocrmDirectory="$(dirname "$(readlink -f "$BASH_SOURCE")")"

action=${1:-help}
option=${2:-}

case "$action" in
    help )
        actionHelp
        ;;

    rebuild )
        actionRebuild
        ;;

    restart )
        actionRestart "$option"
        ;;

    start )
        actionStart "$option"
        ;;

    status )
        actionStatus
        ;;

    stop )
        actionStop "$option"
        ;;

    build )
        actionBuild
        ;;

    upgrade )
        actionUpgrade "$option"
        ;;

    clean )
        actionClean
        ;;

    logs )
        actionLogs
        ;;

    backup )
        actionBackup "$option"
        ;;
esac
