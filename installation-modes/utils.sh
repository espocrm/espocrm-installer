#!/bin/bash

function handleParams() {
    for ARGUMENT in "$@"
    do
        local key=$(echo "$ARGUMENT" | cut -f1 -d=)
        local value=$(echo "$ARGUMENT" | cut -f2 -d=)

        case "$key" in
            --server)
                server="${value}"
                ;;

            --domain)
                domain="${value}"
                ;;

            --url)
                url="${value}"
                ;;

            --dbRootPassword)
                dbRootPassword="${value}"
                ;;

            --dbPassword)
                dbPassword="${value}"
                ;;

            --adminUsername)
                adminUsername="${value}"
                ;;

            --adminPassword)
                adminPassword="${value}"
                ;;

            --email)
                email="${value}"
                ;;

            --homeDirectory)
                homeDirectory="${value}"
                ;;
        esac
    done
}

function prepareConfiguration() {
    declare -A values=(
        ["DOMAIN_NAME"]="$domain"
        ["ESPOCRM_SITE_URL"]="$url"
        ["DB_ROOT_PASSWORD"]="$dbRootPassword"
        ["DB_PASSWORD"]="$dbPassword"
        ["ADMIN_USERNAME"]="$adminUsername"
        ["ADMIN_PASSWORD"]="$adminPassword"
        ["EMAIL"]="${email:-}"
        ["HOME_DIRECTORY"]="$homeDirectory"
    )

    find "./$server" -type f  | while read file; do
        for key in "${!values[@]}"
        do
            local value="${values[$key]}"
            sed -i "s#%%${key}%%#${value}#g" "$file"
        done
    done
}

function createDockerNetwork() {
    local networkName="$1"

    docker network inspect "$networkName" >/dev/null 2>&1 || docker network create "$networkName"
}
