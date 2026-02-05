#!/bin/bash

# EspoCRM installer MASTER
#
# EspoCRM - Open Source CRM application.
# Copyright (C) 2014-2026 EspoCRM, Inc.
# Website: https://www.espocrm.com

set -e

if ! [ $(id -u) = 0 ]; then
    printf "ERROR: This script should be run as root or with sudo.\n"
    exit 1
fi

function actionHelp() {
    printf "Available commands:\n"

    printf "  status                Status of services\n"
    printf "  restart               Restart services\n"
    printf "  start                 Start services\n"
    printf "  stop                  Stop services\n"
    printf "  build                 Build and start services\n"
    printf "  rebuild               Run EspoCRM rebuild\n"
    printf "  upgrade               Upgrade all EspoCRM services\n"
    printf "  clean                 Remove old and unused data\n"
    printf "  logs                  See the EspoCRM container logs\n"
    printf "  backup                Backup all EspoCRM services\n"
    printf "  restore               Restore the backup\n"
    printf "  import-sql            Import database data by SQL dump\n"
    printf "  export-sql            Export database data into SQL dump\n"
    printf "  export-table-sql      Export a single database table into SQL dump\n"
    printf "  cert-generate         Generate a new Let's Encrypt certificate\n"
    printf "  cert-renew            Renew an existing Let's Encrypt certificate\n"
    printf "  cert-cron-add         Add a cronjob for automatic renewal Let's Encrypt certificates\n"
    printf "  cert-cron-remove      Remove a cronjob for automatic renewal Let's Encrypt certificates\n"
    printf "  apply-domain          Apply a domain change\n"
    printf "  voip-cron-add         Add a cronjob for a VoIP connector\n"
    printf "  voip-cron-remove      Remove a cronjob for a VoIP connector\n"
    printf "  help                  Information about the commands\n"
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

function addCron() {
    local search="$1"
    local cronLine="$2"

    if ! crontab -l > /dev/null 2>&1; then
        echo "" | sudo crontab -
    fi

    local hasCron=$(sudo crontab -l | grep -i "$search")

    if [ -z "$hasCron" ]; then
        (sudo crontab -l; echo "$cronLine") | sudo crontab -
    fi
}

function removeCron() {
    local search="$1"

    local hasCron=$(sudo crontab -l | grep -i "$search")

    if [ -n "$hasCron" ]; then
        crontab -l | grep -vi "$search" | sudo crontab -
    fi
}

function actionRebuild() {
    docker exec --user www-data -i espocrm /bin/bash -c "php command.php rebuild"
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

    if [ ! -f "${homeDirectory}/docker-compose.yml" ]; then
        return
    fi

    docker compose -f "${homeDirectory}/docker-compose.yml" down
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

    actionStop > /dev/null 2>&1

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

    case "$(getActualInstalledMode)" in
        letsencrypt )
            actionCertCronAdd
            ;;
    esac

    echo "Done"
}

function actionImportSql() {
    local sqlFile=${1:-}
    local skipDrop=${2:-}

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

    if [ "$skipDrop" != true ]; then
        docker exec -i espocrm-db mariadb --user=root --password="$dbRootPass" -e "DROP DATABASE $dbName; CREATE DATABASE $dbName;" > /dev/null 2>&1 || {
            echo "ERROR: Unable to clean the database."
            exit 1
        }
    fi

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

    # Run temporary nginx
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

function actionCertCronAdd() {
    addCron "command.sh cert-renew" "0 1 * * * $homeDirectory/command.sh cert-renew >> $homeDirectory/data/letsencrypt/renew.log 2>&1"
}

function actionCertCronRemove() {
    removeCron "command.sh cert-renew"
}

function actionApplyDomain() {
    case "$(getActualInstalledMode)" in
        letsencrypt )
            actionStop
            actionCertGenerate
            actionBuild
            actionCertCronAdd
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

function actionExportSql() {
    local backupPath=${1:-}
    local tableName=${2:-}
    local fileName=${3:-"espocrm"}

    if [ -z "$backupPath" ]; then
        echo "ERROR: The path is not specified, ex. export-sql /var/www/backup"
        exit 1
    fi

    if [[ "$backupPath" != *".sql" ]]; then
        backupPath=$(echo "$backupPath" | sed 's/\/$//')
        backupPath="$backupPath/$fileName.sql"
    fi

    directory=$(dirname "$backupPath")

    if [ ! -d "$directory" ]; then
        mkdir -p "$directory"
    fi

    touch "$backupPath" || {
        echo "ERROR: Permission denied to create the $backupPath file."
        exit 1
    }

    local freeSpace=$(freeSpace)
    local usedSpace=$(usedSpace)
    usedSpace=$(( 2*usedSpace ))

    if [[ $freeSpace -lt $usedSpace ]]; then
        echo "ERROR: Insufficient disk space."
        exit 1
    fi;

    echo "Exporting the database..."

    local dbName=$(getYamlValue "MARIADB_DATABASE" espocrm-db)
    local dbRootPass=$(getYamlValue "MARIADB_ROOT_PASSWORD" espocrm-db)

    if [ -n "$tableName" ]; then
        docker exec -i espocrm-db mariadb-dump --user=root --password="$dbRootPass" "$dbName" "$tableName" > "$backupPath" || {
            echo "ERROR: Unable to export the database."
            exit 1
        }
    else
        docker exec -i espocrm-db mariadb-dump --user=root --password="$dbRootPass" "$dbName" > "$backupPath" || {
            echo "ERROR: Unable to export the database."
            exit 1
        }
    fi

    local backupPathArchived="$backupPath.tar.gz"

    tar -czf "$backupPathArchived" -C $(dirname "$backupPath") $(basename "$backupPath") > /dev/null 2>&1 || {
        echo "Done."
        echo "Saved to $backupPath"

        return
    }

    rm -f "$backupPath"

    echo "Done."
    echo "Saved to $backupPathArchived"
}

function actionExportTableSql() {
    local backupPath=${1:-}
    local tableName=${2:-}

    if [ -z "$backupPath" ]; then
        echo "ERROR: The path is not specified, ex. export-table-sql /var/www/backup account"
        exit 1
    fi

    if [ -z "$tableName" ]; then
        echo "ERROR: Table name is not specified, ex. export-table-sql /var/www/backup account"
        exit 1
    fi

    actionExportSql "$backupPath" "$tableName" "$tableName"
}

function actionVoipCronAdd() {
    local connector=${1:-}

    if [ -z "$connector" ]; then
        echo "ERROR: The VoIP connector is not specified, ex. \"voip-cron-add Asterisk\""
        exit 1
    fi

    addCron "command.php voip $connector" "* * * * * docker exec --user www-data -i espocrm /bin/bash -c \"cd /var/www/html; php -f command.php voip $connector\" >> $homeDirectory/data/voip-cron.log 2>&1"
}

function actionVoipCronRemove() {
    local connector=${1:-}

    if [ -z "$connector" ]; then
        echo "ERROR: The VoIP connector is not specified, ex. \"voip-cron-remove Asterisk\""
        exit 1
    fi

    removeCron "command.php voip $connector"
}

homeDirectory="$(dirname "$(readlink -f "$BASH_SOURCE")")"

action=${1:-help}
option=${2:-}
option2=${3:-}

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
        if [ -n "$option" ] && [ "$option2" = "--skip-drop" ]; then
            actionImportSql "$option" true
        elif [ -n "$option2" ] && [ "$option" = "--skip-drop" ]; then
            actionImportSql "$option2" true
        else
            actionImportSql "$option"
        fi
        ;;

    cert-generate )
        actionCertGenerate
        ;;

    cert-renew )
        actionCertRenew
        ;;

    cert-cron-add )
        actionCertCronAdd
        ;;

    cert-cron-remove )
        actionCertCronRemove
        ;;

    apply-domain )
        actionApplyDomain
        ;;

    export-sql )
        actionExportSql "$option"
        ;;

    export-table-sql )
        actionExportTableSql "$option" "$option2"
        ;;

    voip-cron-add )
        actionVoipCronAdd "$option"
        ;;

    voip-cron-remove )
        actionVoipCronRemove "$option"
        ;;
esac
