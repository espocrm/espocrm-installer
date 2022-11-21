#!/bin/bash

# EspoCRM installer MASTER
#
# EspoCRM - Open Source CRM application.
# Copyright (C) 2014-2022 Yurii Kuznietsov, Taras Machyshyn, Oleksii Avramenko
# Website: https://www.espocrm.com

set -e

function printExitError() {
    local message="$1"

    restoreBackup

    printf "\n"
    printRedMessage "ERROR"
    printf ": ${message}\n"

    exit 1
}

printRedMessage() {
    local message="$1"

    local red='\033[0;31m'
    local default='\033[0m'

    printf "${red}${message}${default}"
}

function restoreBackup() {
    if [ -n "$backupDirectory" ] && [ -d "$backupDirectory" ]; then
        cp -rp "${backupDirectory}"/* "${data[homeDirectory]}"
    fi
}

if ! [ $(id -u) = 0 ]; then
    printExitError "This script should be run as root or with sudo."
fi

# Pre installation modes:
# 1. HTTP. Without parameters.
# 2. Ask3. Without parameters, when already installed. It will ask about:
#    1. HTTP
#    2. letsencrypt
#    3. SSL
# 3. Ask2. Parameter --ssl. It will ask about letsencrypt + email.
# 4. SSL. Parameter --ssl --owncertificate. Installation with a set self-signed certificate.
# 5. Letsencrypt. Parameter --ssl --letsencrypt. It will ask for an email address.

preInstallationMode=1

declare -A data=(
    [server]="nginx"
    [ssl]=false
    [owncertificate]=false
    [letsencrypt]=false
    [mysqlRootPassword]=$(openssl rand -hex 10)
    [mysqlPassword]=$(openssl rand -hex 10)
    [adminUsername]="admin"
    [adminPassword]=$(openssl rand -hex 6)
    [homeDirectory]="/var/www/espocrm"
    [action]="main"
    [backupPath]="SCRIPT_DIRECTORY/espocrm-backup"
)

declare -A modes=(
    [1]="letsencrypt"
    [2]="ssl"
    [3]="http"
)

declare -A modesLabels=(
    [letsencrypt]="Let's Encrypt certificate"
    [ssl]="Own SSL/TLS certificate"
    [http]="HTTP only"
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

            --ssl)
                data[ssl]=true
                ;;

            --owncertificate)
                data[owncertificate]=true
                ;;

            --letsencrypt)
                data[letsencrypt]=true
                ;;

            --clean)
                needClean=true
                ;;

            --domain)
                data[domain]="${value}"
                ;;

            --email)
                data[email]="${value}"
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

            --command)
                data[action]="command"
                ;;

            --backup-path)
                data[backupPath]="${value}"
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

function stopProcess() {
    restoreBackup

    echo "Aborted."
    exit 0
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

function getServerIp() {
    local serverIP=$(hostname -I | awk '{print $1}')

    if [ -z "$serverIP" ] || [ "$(isIpAddress $serverIP)" != true ]; then
        serverIP=$(ip route get 1 | awk '{print $NF;exit}')
    fi

    if [ "$(isIpAddress $serverIP)" = true ]; then
        echo "$serverIP"
    fi
}

function getActualInstalledMode() {
    if [ -f "${data[homeDirectory]}/docker-compose.yml" ]; then
        head -n 1 "${data[homeDirectory]}/docker-compose.yml" | grep -oP "(?<=MODE: ).*"
    fi
}

function getInstalltionMode() {
    if [ -z "$installationMode" ] || [ -z "${modes[$installationMode]}" ]; then
        printExitError "Unknown installation mode. Please try again."
    fi

    echo "${modes[$installationMode]}"
}

function getYamlValue {
    local keyName="$1"
    local category="$2"

    if [ -f "${data[homeDirectory]}/docker-compose.yml" ]; then
        sed -n "/${category}:/,/networks:/p" "${data[homeDirectory]}/docker-compose.yml" | grep -oP "(?<=${keyName}: ).*" | head -1
    fi
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

    echo false
}

function isHostAvailable() {
    local hostname=$1

    host $hostname 2>&1 > /dev/null
    if [ $? -eq 0 ]; then
        echo true
        return
    fi

    echo false
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
    if [ -d "${data[homeDirectory]}" ]; then
        echo true
        return
    fi

    if [ -x "$(command -v docker)" ] && [ "$(docker ps -aqf name=espocrm)" ]; then
        echo true
        return
    fi

    echo false
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

function getBackupDirectory() {
    local backupPath="${data[backupPath]}"

    backupPath=${backupPath//SCRIPT_DIRECTORY/$scriptDirectory}
    backupPath=${backupPath%/}

    echo "${backupPath}/$(date +'%Y-%m-%d_%H%M%S')"
}

function backupActualInstallation {
    if [ ! -d "${data[homeDirectory]}" ]; then
        return
    fi

    echo "Creating a backup..."

    backupDirectory=$(getBackupDirectory)

    mkdir -p "${backupDirectory}"

    cp -rp "${data[homeDirectory]}"/* "${backupDirectory}"

    echo "Backup is created: $backupDirectory"
}

function cleanInstallation() {
    printf "Cleaning the previous installation...\n"

    docker compose -f "${data[homeDirectory]}/docker-compose.yml" down

    backupActualInstallation

    rm -rf "${data[homeDirectory]}"
}

function rebaseInstallation() {
    local isRebase=${rebaseInstallation:-false}

    if [ "$isRebase" != true ]; then
        return
    fi

    printf "\n"
    printf "Starting the reinstallation process...\n"

    normalizeActualInstalledData

    backupActualInstallation

    printf "\n"

    docker compose -f "${data[homeDirectory]}/docker-compose.yml" down

    rm -rf "${data[homeDirectory]}/data/${data[server]}"
    rm "${data[homeDirectory]}/docker-compose.yml"
}

function cleanTemporaryFiles() {
    if [ -f "${scriptDirectory}/espocrm-installer-master.zip" ]; then
        rm "${scriptDirectory}/espocrm-installer-master.zip"
    fi

    if [ -d "${scriptDirectory}/espocrm-installer-master" ]; then
        rm -rf "${scriptDirectory}/espocrm-installer-master"
    fi
}

function normalizeActualInstalledData() {
    declare -A currentData

    currentData[mysqlRootPassword]=$(getYamlValue "MYSQL_ROOT_PASSWORD" "espocrm-mysql")
    currentData[mysqlPassword]=$(getYamlValue "MYSQL_PASSWORD" "espocrm-mysql")
    currentData[adminUsername]=$(getYamlValue "ESPOCRM_ADMIN_USERNAME" "espocrm")
    currentData[adminPassword]=$(getYamlValue "ESPOCRM_ADMIN_PASSWORD" "espocrm")

    for key in "${!currentData[@]}"
    do
        local value="${currentData[$key]}"

        if [ -z "$value" ]; then
            printExitError "Unable to start the reinstallation process. If you want to start a clean installation with losing your data, use \"--clean\" option."
        fi

        data[$key]="$value"
    done
}

function normalizePreInstallationMode() {
    if [ "${data[ssl]}" = true ] && [ "${data[owncertificate]}" = true ]; then
        preInstallationMode=4
        return
    fi

    if [ "${data[ssl]}" = true ] && [ "${data[letsencrypt]}" = true ]; then
        preInstallationMode=5
        return
    fi

    if [ "${data[ssl]}" = true ]; then
        preInstallationMode=3
        return
    fi
}

function normalizeData() {
    declare -a requiredFields=(
        domain
    )

    for requiredField in "${requiredFields[@]}"
    do
        if [ -z "${data[$requiredField]}" ]; then
            printExitError "The field \"$requiredField\" is required."
        fi
    done

    if [ "$mode" == "letsencrypt" ]; then
        local isEmailValidated=$(isEmailValidated "${data[email]}")

        if [ -z "${data[email]}" ] || [ "$isEmailValidated" != true ]; then
            printExitError "Empty or incorrect \"email\" field."
        fi
    fi

    data[url]="http://${data[domain]}"
    data[httpPort]="80"

    if [ "$mode" != "http" ]; then
        data[url]="https://${data[domain]}"
        data[httpPort]="443"
    fi

    # Validate domain
    isFqdn=$(isFqdn "${data[domain]}")
    isIpAddress=$(isIpAddress "${data[domain]}")

    if [ "$isFqdn" != true ] && [ "$isIpAddress" != true ]; then
        printExitError "Your domain name or IP: \"${data[domain]}\" is incorrect. Please enter a valid one and try again."
    fi

    if [ "$isFqdn" != true ] && [ "$mode" != "http" ]; then
        printExitError "Your domain name: \"${data[domain]}\" is incorrect. SSL/TLS certificate can only be used for a valid domain name."
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
            restoreBackup
            exit 1
        }
        return
    fi

    "./$script" || {
        restoreBackup
        exit 1
    }
}

function handleExistingInstallation {
    if [ -n "$needClean" ] && [ $needClean = true ]; then
        cleanInstallation || {
            printExitError "Unable to clean existing installation."
        }
    fi

    if [ $(isInstalled) != true ]; then
        return
    fi

    printf "\n"
    printf "The installed EspoCRM instance is found.\n"

    case "$(getActualInstalledMode)" in
        http | letsencrypt | ssl )
            preInstallationMode=2
            rebaseInstallation=true
            ;;

        * )
            printExitError "Unable to determine the current installation mode. If you want to start a clean installation with losing your data, use \"--clean\" option."
            ;;
    esac
}

function handlePreInstallationMode() {
    local mode="$1"

    case "$mode" in
        1 | 2 )
            installationMode=3
            ;;

        3 )
            read -p "
Please choose the installation mode you prefer [1-2]:
  * 1. Free SSL/TLS certificate provided by the Let's Encrypt (recommended)? [1]
  * 2. Own SSL/TLS certificate (for advanced users only)? [2]
" installationMode
            ;;

        4 )
            installationMode=2
            ;;

        5 )
            installationMode=1
            ;;

        * )
            printExitError "Unknown installation mode. Please try to run the script again."
            ;;
    esac
}

function handleInstallationMode() {
    local mode="$1"

    case "$mode" in
        1 )
            if [ -z "${data[email]}" ]; then
                printf "\n"
                read -p "Specify your email address to generate the Let's Encrypt certificate: " data[email]
            fi
            ;;

        2 )
            printf "NOTICE: For using your own SSL/TLS certificates you have to setup them manually after the installation.\n"
            sleep 1
            ;;

        3 )
            if [ -z "${data[domain]}" ]; then
                data[domain]=$(getServerIp)

                isIpAddress=$(isIpAddress "${data[domain]}")
                if [ "$isIpAddress" != true ]; then
                    printf "\n"
                    read -p "Enter a domain name or IP for the future EspoCRM instance (e.g. 234.32.0.32 or espoexample.com)" data[domain]
                fi
            fi
            ;;

        * )
            printExitError "Incorrect installation mode. Please try again."
            ;;
    esac

    if [ -z "${data[domain]}" ]; then
        printf "\n"
        read -p "Enter a domain name for the future EspoCRM instance (e.g. espoexample.com): " data[domain]
    fi
}

function downloadSourceFiles() {
    rm -rf ./espocrm-installer-master.zip ./espocrm-installer-master/

    download https://github.com/espocrm/espocrm-installer/archive/refs/heads/master.zip "espocrm-installer-master.zip"
    unzip -q "espocrm-installer-master.zip"

    if [ ! -d "./espocrm-installer-master" ]; then
        printExitError "Unable to load source files."
    fi
}

function prepareDocker() {
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

    # Correct existing params
    local configFile="${data[homeDirectory]}/data/espocrm/data/config.php"

    if [ -f "$configFile" ]; then
        sed -i "s#'siteUrl' => '.*'#'siteUrl' => '${data[url]}'#g" "$configFile"
    fi
}

runDockerDatabase() {
    docker compose -f "${data[homeDirectory]}/docker-compose.yml" up -d espocrm-mysql || {
        restoreBackup
        exit 1
    }

    printf "\nWaiting for the database ready.\n"

    local dbUser=$(getYamlValue "MYSQL_USER" espocrm-mysql)
    local dbPass=$(getYamlValue "MYSQL_PASSWORD" espocrm-mysql)

    for i in {1..36}
    do
        docker exec -i espocrm-mysql mysql --user="$dbUser" --password="$dbPass" -e "SHOW DATABASES;" > /dev/null 2>&1 && break

        printf "."

        sleep 5
    done

    printf "\n"
}

function runDocker() {
    runDockerDatabase

    docker compose -f "${data[homeDirectory]}/docker-compose.yml" up -d || {
        restoreBackup
        exit 1
    }

    printf "\nWaiting for the first-time EspoCRM configuration.\n"
    printf "This may take up to 5 minutes.\n"

    for i in {1..120}
    do
        if [ $(curl -sfkLI "${data[url]}" --resolve "${data[domain]}:${data[httpPort]}:127.0.0.1" -o /dev/null -w '%{http_code}\n') == "200" ]; then
            runDockerResult=true
            return
        fi

        printf "."

        if [ $i -eq 61 ]; then
            printf "\n\nYour server is running slow. In 90%% the process is faster.\n"
            printf "You have to wait 5 more minutes.\n"
        fi

        sleep 5
    done

    runDockerResult=false
}

function displaySummaryInformation() {
    printf "\n"
    printf "Summary information:\n"
    printf "  Domain: ${data[domain]}\n"
    printf "  Mode: ${modesLabels[$mode]}\n"

    if [ "$mode" == "letsencrypt" ]; then
        printf "  Email for the Let's Encrypt certificate: ${data[email]}\n"
    fi

    isConfirmed=$(promptConfirmation "Do you want to continue? [y/n] ")
    if [ "$isConfirmed" != true ]; then
        stopProcess
    fi
}

#---------- ACTIONS --------------------

function actionMain() {
    if [ -z "$noConfirmation" ]; then
        printf "This script will install EspoCRM with all the needed prerequisites (including Docker, Docker-compose, Nginx, PHP, MySQL).\n"

        isConfirmed=$(promptConfirmation "Do you want to continue the installation? [y/n] ")
        if [ "$isConfirmed" != true ]; then
            stopProcess
        fi
    fi

    handleExistingInstallation

    normalizePreInstallationMode

    handlePreInstallationMode "$preInstallationMode"
    handleInstallationMode "$installationMode"

    mode=$(getInstalltionMode)

    normalizeData

    if [ -z "$noConfirmation" ]; then
        displaySummaryInformation
    fi

    rebaseInstallation

    checkFixSystemRequirements "$operatingSystem"

    cleanTemporaryFiles

    downloadSourceFiles

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

    # Prepare docker
    prepareDocker

    # Run Docker
    runDocker

    printf "\n\n"

    if [ "$runDockerResult" = true ]; then
        printf "The installation has been successfully completed.\n"
    else
        printRedMessage "The installation process is still in progress due to low server performance.\n"
        printf " - In order to check the process, run:\n"
        printf "   ${data[homeDirectory]}/command.sh logs\n"
        printf " - In order to cancel the process, run:\n"
        printf "   ${data[homeDirectory]}/command.sh stop\n"
    fi

    # Post installation message
    case $mode in
        http )
            printf "
IMPORTANT: Your EspoCRM instance is working in HTTP mode.
If you want to install with SSL/TLS certificate, use \"--ssl\" option. For more details, please visit https://docs.espocrm.com/administration/installation-by-script#installation-with-ssltls-certificate.
"
            ;;

        ssl )
            printf "
IMPORTANT: Your EspoCRM instance is working in insecure mode with a self-signed certificate.
You have to setup your own SSL/TLS certificates. For more details, please visit https://docs.espocrm.com/administration/installation-by-script#2-own-ssltls-certificate.
"
            ;;
    esac

    printf "
Login data/information to your EspoCRM instance:
URL: ${data[url]}
Username: ${data[adminUsername]}
Password: ${data[adminPassword]}
"

    printf "\nYour instance files are located at: \"${data[homeDirectory]}\".\n"
}

actionCommand() {
    downloadSourceFiles

    if [ ! -f "${data[homeDirectory]}/command.sh" ]; then
        printExitError "EspoCRM directory is not found."
    fi

    cp ./espocrm-installer-master/commands/command.sh "${data[homeDirectory]}/command.sh" || {
        printExitError "Unable to update the ${data[homeDirectory]}/command.sh"
    }

    echo "Done"
}

#---------------------------------------

scriptDirectory="$(dirname "$(readlink -f "$BASH_SOURCE")")"
operatingSystem=$(getOs)

handleArguments "$@"

# run an action

case "${data[action]}" in
    main )
        actionMain
        ;;

    command )
        actionCommand
        ;;

    * )
        printExitError "Unknown action \"{data[action]}\"."
        ;;
esac

cleanTemporaryFiles
