#!/usr/bin/env bash

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { printf '%s\n' "index.sh: this file should not be run externally." >&2; exit 2; }
[[ -n "${INDEX_LOADED:-}" ]] && return 0
INDEX_LOADED=1

__dir="${BASH_SOURCE[0]%/*}"
[[ "${__dir}" == "${BASH_SOURCE[0]}" ]] && __dir="."

__core_dir="$(cd -- "${__dir}" && pwd -P)"

source "${__core_dir}/env.sh"
source "${__core_dir}/parse.sh"
source "${__core_dir}/pkg.sh"
source "${__core_dir}/tool.sh"
source "${__core_dir}/fs.sh"

unset  __dir __core_dir
