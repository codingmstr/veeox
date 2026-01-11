#!/usr/bin/env bash

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { printf '%s\n' "boot.sh: this file should not be run externally." >&2; exit 2; }
[[ -n "${BOOT_LOADED:-}" ]] && return 0
BOOT_LOADED=1

__dir="${BASH_SOURCE[0]%/*}"
[[ "${__dir}" == "${BASH_SOURCE[0]}" ]] && __dir="."

BASE_DIR="$(cd -- "${__dir}" && pwd -P)/.."
CORE_DIR="${BASE_DIR}/core"
MODULE_DIR="${BASE_DIR}/module"

source "${CORE_DIR}/env.sh"
source "${CORE_DIR}/parse.sh"
source "${CORE_DIR}/pkg.sh"
source "${CORE_DIR}/tool.sh"
source "${CORE_DIR}/fs.sh"
