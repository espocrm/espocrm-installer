#!/bin/bash

set -e

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
    printf "  restore     Restore the backup\n"
    printf "  help        Information about the commands\n"
}

function promptConfirmation() {
    local text=$1

    read -p "${text}" choice

    case "$choice" in
        y|Y|yes|YES )
            echo true
            return
            ;;
    esac

    echo false
}

function freeSpace() {
    df -k --output=avail "$homeDirectory" | tail -n1
}

function usedSpace() {
    du -s "$homeDirectory" | awk '{print $1}'
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
        docker-compose -f "$homeDirectory/docker-compose.yml" up -d "$1"
        return
    fi

    docker-compose -f "$homeDirectory/docker-compose.yml" up -d
}

function actionStatus() {
    docker ps -f "name=espocrm"
}

function actionStop() {
    docker-compose -f "$homeDirectory/docker-compose.yml" down
}

function actionBuild() {
    docker-compose -f "$homeDirectory/docker-compose.yml" up -d --build "$@"
    docker-compose up --build -d
}

function actionUpgrade() {
    docker-compose -f "$homeDirectory/docker-compose.yml" pull
    docker-compose -f "$homeDirectory/docker-compose.yml" up -d
}

function actionClean() {
    docker image prune -f
}

function actionLogs() {
    docker logs espocrm
}

function actionBackup() {
    local backupPath=${1:-"/var/www/espocrm-backup"}

    backupPath=${backupPath%/}
    backupFilePath="${backupPath}/$(date +'%Y-%m-%d_%H%M%S').tar.gz"

    if [ ! -f "${homeDirectory}/docker-compose.yml" ]; then
        echo "ERROR: The EspoCRM is not found."
        exit 1
    fi

    echo "Creating a backup..."

    mkdir -p "${backupPath}" || {
        exit 1
    }

    local usedSpace=$(usedSpace)
    local freeSpace=$(freeSpace)

    if [[ $freeSpace -lt $usedSpace ]]; then
        echo "ERROR: Insufficient disk space."
        exit 1
    fi

    tar --warning=no-file-changed --exclude="*.log" -czf "${backupFilePath}" -C "${homeDirectory}" . > /dev/null 2>&1 || {
        local errorCode=$?

        if [ "$errorCode" != "1" ] && [ "$errorCode" != "0" ]; then
            echo "ERROR: Unable to create an archive, error code: $errorCode."
            exit 1
        fi
    }

    echo "Backup is created: ${backupFilePath}"
}

function actionRestore() {
    local backupFile=${1:-}

    if [ -z "$backupFile" ]; then
        echo "ERROR: Backup file is not specified."
        exit 1
    fi

    if [ ! -f "$backupFile" ]; then
        echo "ERROR: The backup file \"${backupFile}\" is not found."
        exit 1
    fi

    local backupFileName=$(basename "$backupFile")

    echo "All current data will be DELETED and restored with the \"${backupFileName}\" backup."

    local isConfirmed=$(promptConfirmation "Do you want to continue? [y/n] ")

    if [ "$isConfirmed" != true ]; then
        echo "Canceled"
        exit 0
    fi

    local freeSpace=$(freeSpace)
    local usedSpace=$(usedSpace)
    usedSpace=$(( 2*usedSpace ))

    if [[ $freeSpace -lt $usedSpace ]]; then
        echo "ERROR: Insufficient disk space."
        exit 1
    fi;

    actionStop

    rm -rf "${homeDirectory}_OLD"

    mv "${homeDirectory}" "${homeDirectory}_OLD"

    mkdir -p "${homeDirectory}"

    tar -xzf "$backupFile" -C "${homeDirectory}" || {
        printf "ERROR: Permission denied to restore the backup.\n\n"

        echo "Restoring the previous data..."

        rm -rf "${homeDirectory}"
        mv "${homeDirectory}_OLD" "${homeDirectory}"
        actionStart
        exit 1
    }

    actionStart

    rm -rf "${homeDirectory}_OLD"

    echo "Done"
}

homeDirectory="$(dirname "$(readlink -f "$BASH_SOURCE")")"

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

    restore )
        actionRestore "$option"
        ;;
esac
