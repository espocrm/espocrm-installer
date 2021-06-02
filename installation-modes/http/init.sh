#!/bin/bash

set -euo pipefail

if ! [ $(id -u) = 0 ]; then
   printf "Error: this script must be run as root\n"
   exit 1
fi

source installation-modes/utils.sh

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

handleParams "$@"

prepareConfiguration

createDockerNetwork "external"
