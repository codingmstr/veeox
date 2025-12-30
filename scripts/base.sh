#!/usr/bin/env bash
set -Eeuo pipefail

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { echo "This file must be sourced, not executed." >&2; exit 2; }
[[ -n "${VX_BASE_SH_LOADED:-}" ]] && return 0
VX_BASE_SH_LOADED=1

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SELF="$SCRIPT_DIR/run.sh"

declare -ar VX_SKIP_MODULES=("base" "run" "install")

IFS=$'\n\t'
VX_YES="${VX_YES:-0}"
VX_QUIET="${VX_QUIET:-0}"
VX_VERBOSE="${VX_VERBOSE:-0}"

cd_root () {

    cd -- "${ROOT_DIR}"

}
log () {

    (( VX_QUIET )) && return 0
    printf '%s\n' "$@"

}
elog () {

    printf '%s\n' "$@" >&2

}
die () {

    elog "${1}"
    exit "${2:-1}"

}
run () {

    if (( VX_VERBOSE )); then
        {
            printf '+'
            for a in "$@"; do
                printf ' %q' "${a}"
            done
            printf '\n'
        } >&2
    fi

    "$@"

}
has_cmd () {

    command -v "${1}" >/dev/null 2>&1

}
need_cmd () {

    local bin="${1}"
    command -v "${bin}" >/dev/null 2>&1 || die "Missing command: ${bin}" 2

}
path_expand () {

    local p="${1:-}"
    [[ -n "${p}" ]] || { printf '\n'; return 0; }

    p="${p/#\~/${HOME}}"
    printf '%s' "${p}"

}
need_file () {

    local path=""
    path="$(path_expand "${1:-}")"
    [[ -f "${path}" ]] || die "Missing file: ${path}" 2

}
need_node () {

    has_cmd npx || die "npx is not installed. Install Node.js (includes npm/npx)." 2

}
is_ci () {

    [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ]]

}
is_wsl () {

    [[ -n "${WSL_DISTRO_NAME:-}" ]] && return 0
    grep -qi microsoft /proc/version 2>/dev/null

}
confirm () {

    local msg="${1:-Continue?}"

    (( VX_YES )) && return 0
    is_ci && die "Refusing interactive prompt in CI." 2

    local ans=""
    read -r -p "${msg} [y/N]: " ans < /dev/tty 2>/dev/null || true
    [[ "${ans}" == "y" || "${ans}" == "Y" ]]

}
env_is_name () {

    [[ "${1:-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]

}
env_get () {

    local name="${1:-}"
    [[ -n "${name}" ]] || { printf ''; return 0; }

    env_is_name "${name}" || die "Invalid env var name: ${name}" 2
    printf '%s' "${!name:-}"

}
open_path () {

    local path=""
    path="$(path_expand "${1:-}")"
    [[ -n "${path}" ]] || die "Error: open_path requires a path" 2

    is_ci && die "Refusing to open browser in CI." 2

    if has_cmd wslview; then
        wslview "${path}" >/dev/null 2>&1 || true
        return 0
    fi
    if is_wsl && has_cmd wslpath && has_cmd explorer.exe; then
        explorer.exe "$(wslpath -w "${path}")" >/dev/null 2>&1 || true
        return 0
    fi
    if has_cmd xdg-open; then
        xdg-open "${path}" >/dev/null 2>&1 || true
        return 0
    fi
    if has_cmd open; then
        open "${path}" >/dev/null 2>&1 || true
        return 0
    fi

    die "No opener found (wslview/explorer.exe/xdg-open/open)." 2

}
on_err () {

    local ec=$?
    local src="${BASH_SOURCE[1]-${BASH_SOURCE[0]}}"
    local line="${BASH_LINENO[0]-0}"
    local cmd="${BASH_COMMAND-}"

    elog "Error: ${src}:${line} -> ${cmd}"
    exit "${ec}"

}
should_skip () {

    local s name="${1:-}"
    shift || true

    [[ -n "${name}" ]] || return 0
    [[ "${name}" == _* ]] && return 0

    for s in "${VX_SKIP_MODULES[@]}"; do
        [[ "${name}" == "${s}" ]] && return 0
    done
    for s in "$@"; do
        [[ "${name}" == "${s}" ]] && return 0
    done

    return 1

}
source_loader () {

    local dir="${1:-${SCRIPT_DIR}}"
    shift || true

    [[ -n "${dir}" ]] || die "source_loader: missing dir" 2
    [[ -d "${dir}" ]] || die "source_loader: not a dir: ${dir}" 2

    local -a extra_skip=( "$@" )
    local file base
    local nullglob_was_set=0

    shopt -q nullglob && nullglob_was_set=1
    shopt -s nullglob

    for file in "${dir}"/*.sh; do

        base="${file##*/}"
        base="${base%.sh}"

        should_skip "${base}" "${extra_skip[@]}" && continue

        source "${file}" >/dev/null 2>&1 || {
            (( VX_VERBOSE )) && elog "warn: failed to source: ${file}"
            continue
        }

    done

    (( nullglob_was_set )) || shopt -u nullglob

}
doc_render () {

    local dir="${SCRIPT_DIR}"

    printf '%s\n' \
        '' \
        'Usage:' \
        '    vx [--yes] [--quiet] [--verbose] <cmd> [args...]' \
        '' \
        'Global:' \
        '    --yes,    -y     Non-interactive (assume yes)' \
        '    --quiet,  -q     Less output' \
        '    --verbose,-v     Print executed commands'

    local file name mod fn1 fn2 title chosen
    local printed=0
    local nullglob_was_set=0

    shopt -q nullglob && nullglob_was_set=1
    shopt -s nullglob

    for file in "${dir}"/*.sh; do

        name="${file##*/}"
        name="${name%.sh}"

        should_skip "${name}" && continue

        mod="${name//-/_}"
        mod="${mod//./_}"

        fn1="help_${mod}"
        fn2="${mod}_help"
        chosen=""

        declare -F "${fn1}" >/dev/null 2>&1 && chosen="${fn1}"
        [[ -z "${chosen}" ]] && declare -F "${fn2}" >/dev/null 2>&1 && chosen="${fn2}"

        if [[ -z "${chosen}" ]]; then
            source "${file}" >/dev/null 2>&1 || { (( VX_VERBOSE )) && elog "warn: failed to source: ${file}"; continue; }

            declare -F "${fn1}" >/dev/null 2>&1 && chosen="${fn1}"
            [[ -z "${chosen}" ]] && declare -F "${fn2}" >/dev/null 2>&1 && chosen="${fn2}"
        fi

        [[ -n "${chosen}" ]] || continue

        title="${mod//_/ }"
        title="${title^}"

        printf '\n%s:\n' "${title}"
        "${chosen}"

        printed=1

    done

    echo
    (( nullglob_was_set )) || shopt -u nullglob
    (( printed )) || printf '\n(no module help found)\n'

}
parse () {

    VX_CMD="help"
    VX_ARGS=()

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -h|--help)      VX_CMD="help"; shift || true ;;
            --yes|-y)       VX_YES=1; shift || true ;;
            --quiet|-q)     VX_QUIET=1; shift || true ;;
            --verbose|-v)   VX_VERBOSE=1; shift || true ;;
            --)             shift || true; break ;;
            -*)             die "Unknown global flag: ${1}" 2 ;;
            *)              break ;;
        esac
    done

    if [[ $# -gt 0 ]]; then
        VX_CMD="${1}"
        shift || true
        VX_ARGS=( "$@" )
    else
        VX_CMD="help"
        VX_ARGS=()
    fi

}
dispatch () {

    local cmd="${1:-help}"
    shift || true

    case "${cmd}" in
        help|-h|--help)
            doc_render "$@"
            return 0
        ;;
    esac

    if ! [[ "${cmd}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
        log "Unknown command: ${cmd}"
        log
        doc_render
        exit 2
    fi

    local fn="cmd_${cmd//-/_}"
    declare -F "${fn}" >/dev/null 2>&1 && { "${fn}" "$@"; return 0; }

    log "Unknown command: ${cmd}"
    log
    doc_render
    exit 2

}
boot () {

    trap on_err ERR

    source_loader

    parse "$@"
    dispatch "${VX_CMD}" "${VX_ARGS[@]}"

}
