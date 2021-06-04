#!/bin/bash

set -e

function printExitError() {
    local messsage="$1"

    local red='\033[0;31m'
    local default='\033[0m'

    printf "\n${red}ERROR${default}: ${messsage}\n"
    exit 1
}

if ! [ $(id -u) = 0 ]; then
    printExitError "This script should be run as root or with sudo."
fi

declare -A defaults=(
    [server]="nginx"
    [mode]=1
    [mysqlRootPassword]=$(openssl rand -hex 10)
    [mysqlPassword]=$(openssl rand -hex 10)
    [adminUsername]="admin"
    [adminPassword]=$(openssl rand -hex 6)
    [homeDirectory]="/var/www/espocrm"
)

declare -A modes=(
    [1]="http"
    [2]="letsencrypt"
    [3]="ssl"
)

declare -A modesLabels=(
    [1]="HTTP only"
    [2]="Let's Encrypt certificate"
    [3]="Own SSL/TLS certificate"
)

function handleArguments() {
    for ARGUMENT in "$@"
    do
        local key=$(echo "$ARGUMENT" | cut -f1 -d=)
        local value=$(echo "$ARGUMENT" | cut -f2 -d=)

        case "$key" in
            -y|--yes)
                noConfirmation=true
                ;;

            --clean)
                needClean=true
                ;;

            --mode)
                data[mode]="${value}"
                ;;

            --domain)
                data[domain]="${value}"
                ;;

            --email)
                data[email]="${value}"
                ;;

            --homeDirectory)
                data[homeDirectory]="${value}"
                ;;

            --mysqlRootPassword)
                data[mysqlRootPassword]="${value}"
                ;;

            --mysqlPassword)
                data[mysqlPassword]="${value}"
                ;;

            --adminUsername)
                data[adminUsername]="${value}"
                ;;

            --adminPassword)
                data[adminPassword]="${value}"
                ;;
        esac
    done
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

function getOs() {
    local osType="unknown"

    case $(uname | tr '[:upper:]' '[:lower:]') in
        linux*)
            local linuxString=$(cat /etc/*release | grep ^NAME | tr -d 'NAME="' | tr '[:upper:]' '[:lower:]')

            declare -a linuxOsList=(centos redhat fedora ubuntu debian mint)
            for linuxOs in "${linuxOsList[@]}"
            do
                if [[ $linuxString == "$linuxOs"* ]]; then
                    osType="$linuxOs"
                    break
                fi
            done
            ;;
        darwin*)
            osType="osx"
            ;;
        msys*)
            osType="windows"
            ;;
    esac

    echo "$osType"
}

function getHostname() {
    local hostname=$(hostname -f)

    if [ $hostname != "localhost" ]; then
        isFqdn=$(isFqdn "$hostname")

        if [ "$isFqdn" != true ]; then
            hostname=$(getServerIp)
        fi
    fi

    echo "$hostname"
}

function isFqdn() {
    local hostname=$1

    if [ -z "$hostname" ]; then
        echo false
        return
    fi

    local isIpAddress=$(isIpAddress "$hostname")
    if [ "$isIpAddress" = true ]; then
        echo false
        return
    fi

    if [[ $hostname == *"."* ]]; then
        echo true
        return
    fi

    host $hostname 2>&1 > /dev/null
    if [ $? -eq 0 ]; then
        echo true
        return
    fi

    echo false
}

function getServerIp() {
    local serverIP=$(ip route get 1 | awk '{print $NF;exit}')

    if [ -z "$serverIP" ]; then
        serverIP=$(hostname -I | awk '{print $1}')
    fi

    echo "$serverIP"
}

function isIpAddress() {
    local ipAddress="$1"

    if [[ $ipAddress =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo true
        return
    fi

    echo false
}

function isEmailValidated() {
    local emailAddress="$1"

    local regex="^(([A-Za-z0-9]+((\.|\-|\_|\+)?[A-Za-z0-9]?)*[A-Za-z0-9]+)|[A-Za-z0-9]+)@(([A-Za-z0-9]+)+((\.|\-|\_)?([A-Za-z0-9]+)+)*)+\.([A-Za-z]{2,})+$"

    if [[ "$emailAddress" =~ ${regex} ]]; then
        echo true
        return
    fi

    echo false
}

function isInstalled() {
    if [ -f "${data[homeDirectory]}/docker-compose.yml" ]; then
        echo true
        return
    fi

    if [ -x "$(command -v docker)" ] && [ "$(docker ps -aqf name=espocrm)" ]; then
        echo true
        return
    fi

    echo false
}

function cleanInstallation() {
    if [ "$(docker ps -aqf "name=espocrm")" ]; then
        docker stop $(docker ps -aqf "name=espocrm") > /dev/null 2>&1
        docker rm $(docker ps -aqf "name=espocrm") > /dev/null 2>&1
    fi

    if [ -d "${data[homeDirectory]}" ]; then
        backupDirectory="${scriptDirectory}/espocrm-before-clean/$(date +'%Y-%m-%d_%H%M%S')"
        mkdir -p "${backupDirectory}"
        mv "${data[homeDirectory]}"/* "${backupDirectory}"
        sudo rm -rf "${data[homeDirectory]}"
    fi
}

function cleanTemporaryFiles() {
    if [ -f "${scriptDirectory}/espocrm-installer-master.zip" ]; then
        rm "${scriptDirectory}/espocrm-installer-master.zip"
    fi

    if [ -d "${scriptDirectory}/espocrm-installer-master" ]; then
        rm -rf "${scriptDirectory}/espocrm-installer-master"
    fi
}

function normalizeData() {
    declare -a requiredFields=(
        domain
    )

    for param in "${!defaults[@]}"
    do
        if [ -z "${data[$param]}" ]; then
            data[$param]="${defaults[$param]}"
        fi
    done

    for requiredField in "${requiredFields[@]}"
    do
        if [ -z "${data[$requiredField]}" ]; then
            printExitError "The field \"$requiredField\" is required."
        fi
    done

    if [ "${data[mode]}" == "2" ]; then
        local isEmailValidated=$(isEmailValidated "${data[email]}")

        if [ -z "${data[email]}" ] || [ "$isEmailValidated" != true ]; then
            printExitError "Empty or incorrect \"email\" field."
        fi
    fi

    data[url]="http://${data[domain]}"
    data[httpPort]="80"

    if [ "${data[mode]}" != "1" ]; then
        data[url]="https://${data[domain]}"
        data[httpPort]="443"
    fi
}

function createParamsFromData() {
    for field in "${!data[@]}"
    do
        if [ -n "${data[$field]}" ]; then
            params+=("--$field=${data[$field]}")
        fi
    done
}

function checkFixSystemRequirements() {
    local os="$1"

    declare -a missingLibs=()

    if ! [ -x "$(command -v wget)" ] && ! [ -x "$(command -v curl)" ]; then
        missingLibs+=("curl")
    fi

    if ! [ -x "$(command -v unzip)" ]; then
        missingLibs+=("unzip")
    fi

    if [ -z "$missingLibs" ]; then
        return
    fi

    case "$os" in
        ubuntu | debian | mint )
            apt-get update; \
                apt-get install -y --no-install-recommends \
                curl \
                unzip
            ;;

        * )
            printExitError "Missing libraries: ${missingLibs[@]}. Please install them and try again."
            ;;
    esac
}

function displaySummaryInformation() {
    local mode="${data[mode]}"

    printf "Summary information:\n"
    printf "\tDomain: ${data[domain]}\n"
    printf "\tMode: ${modesLabels[$mode]}\n"

    if [ "${data[mode]}" == "2" ]; then
        printf "\tEmail for the Let's Encrypt certificate: ${data[email]}\n"
    fi

    isConfirmed=$(promptConfirmation "Do you want to continue? [y/n] ")
    if [ "$isConfirmed" != true ]; then
        exit 0
    fi
}

function getInstalltionMode() {
    local mode="${data[mode]}"

    if [ -z "${modes[$mode]}" ]; then
        printExitError "Unknown installation mode. Please try again."
    fi

    echo "${modes[$mode]}"
}

function download() {
    local url=$1
    local name=$2

    if [ -x "$(which wget)" ] ; then
        local downloadMode="wget"
    elif [ -x "$(which curl)" ]; then
        local downloadMode="curl"
    fi

    if [ -z "$downloadMode" ]; then
        printExitError "The \"wget\" or \"curl\" is not found on your system. Please install one of them and try again."
    fi

    if [ -n "$name" ]; then
        case $downloadMode in
            wget )
                wget -q $url -O $name
                return
                ;;

            curl )
                curl -o $name -sfL $url
                return
                ;;
        esac
    fi

    case $downloadMode in
        wget )
            wget -q $url
            ;;

        curl )
            curl -sfL $url
            ;;
    esac
}

function runShellScript() {
    local script="$1"
    shift
    local scriptParams=("$@")

    if [ ! -f "./$script" ]; then
        printExitError "Unable to find the \"$script\" script. Try to run the installer again."
    fi

    chmod +x "./$script"

    if [ -n "$scriptParams" ]; then
        "./$script" "${scriptParams[@]}" || {
            exit 1
        }
        return
    fi

    "./$script" || {
        exit 1
    }
}

function printExitError() {
    local messsage="$1"

    local red='\033[0;31m'
    local default='\033[0m'

    printf "\n${red}ERROR${default}: ${messsage}\n"
    exit 1
}

#--------------------------------------------
scriptDirectory="$(dirname "$(readlink -f "$BASH_SOURCE")")"

declare -A data

handleArguments "$@"

operatingSystem=$(getOs)

if [ $(isInstalled) = true ]; then
    printExitError "You already have configured an EspoCRM instance. If you want to start a clean installation, use \"--clean\" option."
fi

if [ -z "$noConfirmation" ]; then
    printf "This script will install EspoCRM and other required third-party components (Docker, Docker-compose, Nginx, PHP, MySQL).\n"

    isConfirmed=$(promptConfirmation "Do you want to continue? [y/n] ")
    if [ "$isConfirmed" != true ]; then
        exit 0
    fi
fi

if [ -z "${data[domain]}" ]; then
    hostname=$(getHostname)

    printf "Enter a domain name or IP for your EspoCRM instance (e.g. example.org)"

    if [ -n "$hostname" ]; then
        printf ". Leave emply for using your hostname \"${hostname}\""
    fi

    printf ": "

    read domain

    if [ -z "$domain" ]; then
        domain="$hostname"
    fi

    data[domain]="$domain"
fi

isFqdn=$(isFqdn "${data[domain]}")
isIpAddress=$(isIpAddress "${data[domain]}")

if [ "$isFqdn" != true ] && [ "$isIpAddress" != true ]; then
    printExitError "Your domain name or IP: \"${data[domain]}\" is incorrect. Please enter a valid one and try again."
fi

if [ -z "${data[mode]}" ] && [ "$isFqdn" = true ]; then
    read -p "Please select the installation mode [1-3]:
  * No SSL/TLS certificate, HTTP only? [1]
  * Free SSL/TLS certificate provided by the Let's Encrypt (recommended)? [2]
  * Own SSL/TLS certificate, for advanced users only? [3]
" data[mode]

    case "${data[mode]}" in
        1 )
            ;;

        2 )
            if [ -z "${data[email]}" ]; then
                read -p "Enter your email address to use the Let's Encrypt certificate: " data[email]
            fi
            ;;

        3 )
            printf "For using your own SSL/TLS certificates you have to copy them to the \"${defaults[homeDirectory]}/data/nginx/ssl\" manually.\n"
            sleep 1
            ;;

        * )
            printExitError "Incorrect installation mode. Please try again."
            ;;
    esac
fi

normalizeData

if [ "$isFqdn" != true ] && [ "${data[mode]}" != "1" ]; then
    printExitError "Your domain name: \"${data[domain]}\" is incorrect. SSL/TLS certificate can only be used for a valid domain name."
fi

if [ -z "$noConfirmation" ]; then
    displaySummaryInformation
fi

if [ -n "$needClean" ] && [ $needClean = true ]; then
    cleanInstallation || {
        printExitError "Unable to clean existing installation."
    }
fi

checkFixSystemRequirements "$operatingSystem"

cleanTemporaryFiles

download https://github.com/espocrm/espocrm-installer/archive/refs/heads/master.zip "espocrm-installer-master.zip"
unzip -q "espocrm-installer-master.zip"

if [ ! -d "./espocrm-installer-master" ]; then
    printExitError "Unable to load required files."
fi

cd "espocrm-installer-master"

# Check and configure a system
case $(getOs) in
    ubuntu | debian | mint )
        runShellScript "system-configuration/debian.sh"
        ;;

    * )
        printExitError "Your OS is not supported by the script. We recommend to use Ubuntu server."
        ;;
esac

# Run installation-modes script
mode=$(getInstalltionMode)

case $mode in
    http | ssl | letsencrypt )
        declare -a params
        createParamsFromData
        runShellScript "installation-modes/$mode/init.sh" "${params[@]}"
        ;;

    * )
        printExitError "Unknown installation mode \"$mode\"."
        ;;
esac

# Prepare docker images
mkdir -p "${data[homeDirectory]}"
mkdir -p "${data[homeDirectory]}/data"
mkdir -p "${data[homeDirectory]}/data/${data[server]}"

if [ ! -d "./installation-modes/$mode/${data[server]}" ]; then
    printExitError "Unable to find configuration for the \"${data[server]}\" server. Try to run the installation again."
fi

if [ ! -f "./installation-modes/$mode/${data[server]}/docker-compose.yml" ]; then
    printExitError "Error: Unable to find \"docker-compose.yml\" file. Try to run the installation again."
fi

mv "./installation-modes/$mode/${data[server]}/docker-compose.yml" "${data[homeDirectory]}/docker-compose.yml"
mv "./installation-modes/$mode/${data[server]}"/* "${data[homeDirectory]}/data/${data[server]}"

# Copy helper commands
find "./commands" -type f  | while read file; do
    fileName=$(basename "$file")
    cp "$file" "${data[homeDirectory]}/$fileName"
    chmod +x "${data[homeDirectory]}/$fileName"
done

# Run Docker
docker-compose -f "${data[homeDirectory]}/docker-compose.yml" up -d || {
    exit 1
}

printf "\nWaiting for the first-time EspoCRM configuration.\n"
printf "This may take up to 5 minutes.\n"

result=false

for i in {1..60}
do
    if [ $(curl -sfkLI "${data[url]}" --resolve "${data[domain]}:${data[httpPort]}:127.0.0.1" -o /dev/null -w '%{http_code}\n') == "200" ]; then
        result=true
        break
    fi

    printf "."
    sleep 5
done

printf "\n\n"

if [ "$result" = true ]; then
    printf "Installation has been successfully completed.\n"
else
    printf "Installation is finished.\n"
fi

if [ "$mode" == "ssl" ]; then
    printf "
IMPORTANT: Your EspoCRM instance is working in insecure mode with a self-signed certificate.
You have to copy your own SSL/TLS certificates to \"${data[homeDirectory]}/data/${data[server]}/data/nginx/ssl\".
"
fi

printf "
Access information to your EspoCRM instance:
  URL: ${data[url]}
  Username: ${data[adminUsername]}
  Password: ${data[adminPassword]}
"

printf "\nAll your files are located at: \"${data[homeDirectory]}\"\n"

if [ -n "$backupDirectory" ]; then
    printf "Backup: $backupDirectory\n"
fi

cleanTemporaryFiles
