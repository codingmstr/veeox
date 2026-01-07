#!/usr/bin/env bash

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { printf '%s\n' "loader.sh: this file should not be run externally." >&2; exit 2; }
[[ -n "${LOADER_LOADED:-}" ]] && return 0
LOADER_LOADED=1

__dir="${BASH_SOURCE[0]%/*}"
[[ "${__dir}" == "${BASH_SOURCE[0]}" ]] && __dir="."
__dir="$(cd -- "${__dir}" && pwd -P)"
source "${__dir}/boot.sh"

should_skip () {

    local name="${1-}" s=""
    shift || true

    [[ -n "${name}" ]] || return 0
    [[ "${name}" == _* ]] && return 0

    for s in "$@"; do
        [[ -n "${s}" ]] || continue
        [[ "${name}" == "${s}" ]] && return 0
    done

    return 1

}
load_source () {

    [[ -n "${MODULES_LOADED-}" ]] && return 0
    MODULES_LOADED=1

    local dir="${1-}"

    if [[ -z "${dir}" ]]; then
        [[ -n "${MODULE_DIR:-}" ]] || { die "load_source: MODULE_DIR not set" 2; return 2; }
        dir="${MODULE_DIR}"
    fi

    [[ -d "${dir}" ]] || { die "load_source: not a dir: ${dir}" 2; return 2; }

    local -a extra_skip=()
    (( $# > 1 )) && extra_skip=( "${@:2}" ) || extra_skip=()

    local file="" base="" name="" nullglob_was_set=0

    shopt -q nullglob && nullglob_was_set=1
    shopt -s nullglob

    for file in "${dir}"/*.sh; do

        base="${file##*/}"
        [[ -n "${base}" ]] || continue

        name="${base%.sh}"
        should_skip "${name}" "${extra_skip[@]-}" && continue

        source "${file}" || {
            (( nullglob_was_set )) || shopt -u nullglob
            die "Failed to source: ${file}" 2
            return 2
        }

    done

    (( nullglob_was_set )) || shopt -u nullglob
    return 0

}
render_doc () {

    local dir="${MODULE_DIR:-}"
    [[ -n "${dir}" ]] || { die "render_doc: MODULE_DIR not set" 2; return 2; }

    load_source "${dir}" || return $?

    printf '%s\n' \
        '' \
        'Usage:' \
        "    __alias__ [--yes] [--quiet] [--verbose] <cmd> [args...]" \
        '' \
        'Global:' \
        '    --yes,    -y     Non-interactive (assume yes)' \
        '    --quiet,  -q     Less output' \
        '    --verbose,-v     Print executed commands' \
        ''

    local nullglob_was_set=0
    shopt -q nullglob && nullglob_was_set=1
    shopt -s nullglob

    local file="" name="" mod="" fn1="" fn2="" fn3="" fn4="" chosen="" title="" printed=0

    for file in "${dir}"/*.sh; do

        name="${file##*/}"
        name="${name%.sh}"

        should_skip "${name}" && continue

        mod="${name//-/_}"
        mod="${mod//./_}"

        fn1="${mod}_usage"
        fn2="help_${mod}"
        fn3="${mod}_help"
        fn4="usage_${mod}"
        chosen=""

        declare -F "${fn1}" >/dev/null 2>&1 && chosen="${fn1}"
        [[ -z "${chosen}" ]] && declare -F "${fn2}" >/dev/null 2>&1 && chosen="${fn2}"
        [[ -z "${chosen}" ]] && declare -F "${fn3}" >/dev/null 2>&1 && chosen="${fn3}"
        [[ -z "${chosen}" ]] && declare -F "${fn4}" >/dev/null 2>&1 && chosen="${fn4}"
        [[ -n "${chosen}" ]] || continue

        title="${mod//_/ }"
        title="$(uc_first "${title}")"

        printf '%s:\n' "${title}"
        "${chosen}" || true

        printed=1

    done

    (( nullglob_was_set )) || shopt -u nullglob
    (( printed )) || printf '%s\n' '(no module usage found)' ''

}
parse_global () {

    MODULE_CMD="h"
    MODULE_ARGS=()

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -h|--help)      MODULE_CMD="h"; shift || true ;;
            --version)      MODULE_CMD="v"; shift || true ;;
            --yes|-y)       YES_ENV=1; shift || true ;;
            --quiet|-q)     QUIET_ENV=1; shift || true ;;
            --verbose|-v)   VERBOSE_ENV=1; shift || true ;;
            --)             shift || true; break ;;
            -*)             die "Unknown global flag: ${1}" 2 ;;
            *)              break ;;
        esac
    done

    if (( $# > 0 )); then
        MODULE_CMD="${1}"
        shift || true
        MODULE_ARGS=( "$@" )
    fi

}
dispatch () {

    local cmd="${1:-}"
    shift || true

    case "${cmd}" in
        h)
            render_doc
            return 0
        ;;
        v)
            echo "1.0.0"
            return 0
        ;;
    esac

    if ! [[ "${cmd}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
        eprint "Unknown command: ( ${cmd} )"
        eprint "See Docs: __alias__ --help"
        return 2
    fi

    local mod="${cmd//-/_}"
    mod="${mod//./_}"

    local sub="${1-}"
    local fn=""

    if [[ -n "${sub}" && "${sub}" != -* ]]; then

        fn="cmd_${mod}_${sub//-/_}"
        fn="${fn//./_}"

        if declare -F "${fn}" >/dev/null 2>&1; then
            shift || true
            "${fn}" "$@"
            return $?
        fi

    fi

    fn="cmd_${mod}"
    fn="${fn//./_}"

    if declare -F "${fn}" >/dev/null 2>&1; then
        "${fn}" "$@"
        return $?
    fi

    eprint "Unknown command: ( ${cmd} )"
    eprint "See Docs: __alias__ --help"
    return 2

}
load () {

    local old_trap="$(trap -p ERR 2>/dev/null || true)"
    if declare -F on_err >/dev/null 2>&1; then trap 'on_err "$?"' ERR; fi

    local dir="${MODULE_DIR:-}"
    [[ -n "${dir}" ]] || { die "load: MODULE_DIR not set" 2; return 2; }

    load_source "${dir}" || return $?
    parse_global "$@"

    local ec=0

    if [[ ${MODULE_ARGS[0]+x} ]]; then
        dispatch "${MODULE_CMD}" "${MODULE_ARGS[@]}"
        ec=$?
    else
        dispatch "${MODULE_CMD}"
        ec=$?
    fi

    if [[ -n "${old_trap}" ]]; then
        eval "${old_trap}"
    else
        trap - ERR 2>/dev/null || true
    fi

    return "${ec}"

}
