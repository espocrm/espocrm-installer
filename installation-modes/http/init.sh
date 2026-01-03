#!/usr/bin/env bash

set -euo pipefail

source installation-modes/utils.sh

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

handleParams "$@"

prepareConfiguration
