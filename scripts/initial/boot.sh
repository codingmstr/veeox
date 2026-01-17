#!/usr/bin/env bash

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { printf '%s\n' "boot.sh: this file should not be run externally." >&2; exit 2; }
[[ -n "${BOOT_LOADED:-}" ]] && return 0
BOOT_LOADED=1

__dir="${BASH_SOURCE[0]%/*}"
[[ "${__dir}" == "${BASH_SOURCE[0]}" ]] && __dir="."

readonly BASE_DIR="$(cd -- "${__dir}" && pwd -P)/.."
readonly CORE_DIR="${BASE_DIR}/core"
readonly MODULE_DIR="${BASE_DIR}/module"

unset __dir 2>/dev/null || true

source "${CORE_DIR}/bash.sh"
source "${CORE_DIR}/env.sh"
source "${CORE_DIR}/parse.sh"
source "${CORE_DIR}/pkg.sh"
source "${CORE_DIR}/tool.sh"
source "${CORE_DIR}/fs.sh"
