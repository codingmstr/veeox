#!/usr/bin/env bash
set -Eeuo pipefail

__dir="${BASH_SOURCE[0]%/*}"
[[ "${__dir}" == "${BASH_SOURCE[0]}" ]] && __dir="."
__dir="$(cd -- "${__dir}" && pwd -P)"

source "${__dir}/initial/installer.sh"
install "$@"
