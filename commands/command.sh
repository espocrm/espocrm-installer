#!/bin/bash

# EspoCRM installer MASTER
#
# EspoCRM - Open Source CRM application.
# Copyright (C) 2014-2022 Yurii Kuznietsov, Taras Machyshyn, Oleksii Avramenko
# Website: https://www.espocrm.com

set -e

if ! [ $(id -u) = 0 ]; then
    printf "ERROR: This script should be run as root or with sudo.\n"
    exit 1
fi

function actionHelp() {
    printf "Available commands:\n"

    printf "  status          Status of services\n"
    printf "  restart         Restart services\n"
    printf "  start           Start services\n"
    printf "  stop            Stop services\n"
    printf "  build           Build and start services\n"
    printf "  rebuild         Run EspoCRM rebuild\n"
    printf "  upgrade         Upgrade all EspoCRM services\n"
    printf "  clean           Remove old and unused data\n"
    printf "  logs            See the EspoCRM container logs\n"
    printf "  backup          Backup all EspoCRM services\n"
    printf "  restore         Restore the backup\n"
    printf "  import-sql      Import database data by SQL dump\n"
    printf "  cert-generate   Generate a new Let's Encrypt certificate\n"
    printf "  cert-renew      Renew an existing Let's Encrypt certificate\n"
    printf "  apply-domain    Apply a domain change\n"
    printf "  help            Information about the commands\n"
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

function getYamlValue {
    local keyName="$1"
    local category="$2"

    if [ -f "${homeDirectory}/docker-compose.yml" ]; then
        sed -n "/${category}:/,/networks:/p" "${homeDirectory}/docker-compose.yml" | grep -oP "(?<=${keyName}: ).*" | head -1
    fi
}

function getActualInstalledMode() {
    if [ -f "$homeDirectory/docker-compose.yml" ]; then
        head -n 1 "$homeDirectory/docker-compose.yml" | grep -oP "(?<=MODE: ).*"
    fi
}

function actionRebuild() {
    /usr/bin/docker exec --user www-data -i espocrm /bin/bash -c "php command.php rebuild"
}

function actionRestart() {
    if [ -n "$1" ]; then
        docker compose -f "$homeDirectory/docker-compose.yml" restart "$1"
        return
    fi

    docker compose -f "$homeDirectory/docker-compose.yml" restart
}

function actionStart() {
    if [ -n "$1" ]; then
        docker compose -f "$homeDirectory/docker-compose.yml" up -d "$1"
        return
    fi

    docker compose -f "$homeDirectory/docker-compose.yml" up -d
}

function actionStatus() {
    docker ps -f "name=espocrm"
}

function actionStop() {
    if [ -n "$1" ]; then
        docker rm -f "$1"
        return
    fi

    docker compose -f "$homeDirectory/docker-compose.yml" down
}

function actionBuild() {
    docker compose -f "$homeDirectory/docker-compose.yml" up -d --build "$@"
}

function actionUpgrade() {
    local backupPath=${1:-}

    actionBackup "$backupPath"

    docker compose -f "$homeDirectory/docker-compose.yml" pull
    docker compose -f "$homeDirectory/docker-compose.yml" up -d
}

function actionClean() {
    docker exec -i espocrm php command.php run-job Cleanup

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

    if [[ ! $backupFileName =~ \.tar\.gz$ ]]; then
        echo "ERROR: File format is not recognized. It should be unzipped .tar.gz file."
        exit 1
    fi

    echo "All current data will be DELETED and RESTORED with the \"${backupFileName}\" backup."

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

function actionImportSql() {
    local sqlFile=${1:-}

    if [ -z "$sqlFile" ]; then
        echo "ERROR: SQL file is not specified."
        exit 1
    fi

    if [ ! -f "$sqlFile" ]; then
        echo "ERROR: The SQL file \"${sqlFile}\" is not found."
        exit 1
    fi

    local sqlFileName=$(basename "$sqlFile")
    local sqlFileExtension="${sqlFileName##*.}"

    if [ "$sqlFileExtension" != "sql" ]; then
        echo "ERROR: File format is not recognized. It should be unzipped .sql file."
        exit 1
    fi

    echo "All current database data will be DELETED and imported with the \"${sqlFileName}\"."
    echo "The backup is required. Use: ${homeDirectory}/command.sh --backup"

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

    echo "Importing the database..."

    local dbName=$(getYamlValue "MARIADB_DATABASE" espocrm-db)
    local dbRootPass=$(getYamlValue "MARIADB_ROOT_PASSWORD" espocrm-db)

    docker exec -i espocrm-db mariadb --user=root --password="$dbRootPass" -e "DROP DATABASE $dbName; CREATE DATABASE $dbName;" > /dev/null 2>&1 || {
        echo "ERROR: Unable to clean the database."
        exit 1
    }

    docker exec -i espocrm-db mariadb --user=root --password="$dbRootPass" "$dbName" < "$sqlFile" || {
        echo "ERROR: Unable to import the database data."
        echo "In order to restore your backup, use \"${homeDirectory}/command.sh --restore\"."
        exit 1
    }

    actionRestart "espocrm-db"

    echo "Done"
}

function actionCertGenerate() {
    local domain=$(getYamlValue "NGINX_HOST" espocrm-nginx)

    mkdir -p "$homeDirectory/data/tmp"

    # Run templorary nginx
    echo "server {
        listen 80;
        listen [::]:80;

        server_name $domain;

        location ~ /.well-known/acme-challenge {
            allow all;
            root /var/www/certbot;
        }
    }" > "$homeDirectory/data/tmp/nginx-default.conf"

    # Check and remove existing espocrm-nginx-tmp
    docker container inspect espocrm-nginx > /dev/null 2>&1 && docker rm -f espocrm-nginx

    # Run espocrm-nginx-tmp
    docker run --name espocrm-nginx \
        -v "$homeDirectory/data/tmp/nginx-default.conf":/etc/nginx/conf.d/default.conf \
        -v "$homeDirectory/data/nginx/ssl":/etc/letsencrypt \
        -v "$homeDirectory/data/nginx/certbot":/var/www/certbot \
        -p 80:80 \
        -d nginx

    # Generate certificates
    docker compose -f "$homeDirectory/docker-compose.yml" run --rm espocrm-certbot

    docker stop espocrm-nginx > /dev/null 2>&1
    docker rm espocrm-nginx > /dev/null 2>&1

    rm -rf "$homeDirectory/data/tmp"
}

function actionCertRenew() {
    printf "%s\n" "$(date)"

    docker container inspect espocrm-certbot > /dev/null 2>&1 && docker rm -f espocrm-certbot

    docker compose -f "$homeDirectory/docker-compose.yml" run --rm espocrm-certbot
    docker compose -f "$homeDirectory/docker-compose.yml" exec espocrm-nginx nginx -s reload

    printf "Done\n\n"
}

function actionApplyDomain() {
    case "$(getActualInstalledMode)" in
        letsencrypt )
            actionStop
            actionCertGenerate
            actionBuild
            ;;

        http | ssl )
            actionStop
            actionBuild
            ;;

        * )
            echo "Error: Unable to apply the domain change, details: unable to determine the installation mode."
            exit 1
            ;;
    esac

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

    import-sql )
        actionImportSql "$option"
        ;;

    cert-generate )
        actionCertGenerate
        ;;

    cert-renew )
        actionCertRenew
        ;;

    apply-domain )
        actionApplyDomain
        ;;
esac
