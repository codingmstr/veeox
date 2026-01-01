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
redact_arg () {

    local a="${1}"

    case "${a}" in

        *x-access-token:*@*)
            local pre="${a%%x-access-token:*}x-access-token:"
            local rest="${a#*x-access-token:}"
            local after="${rest#*@}"
            printf '%s***@%s' "${pre}" "${after}"
            return 0
        ;;

        *=*)
            local k="${a%%=*}"

            case "${k}" in
                *_KEY|KEY_*|KEY|*_TOKEN|TOKEN_*|TOKEN|*_SECRET|SECRET_*|SECRET|*_PASSWORD|PASSWORD_*|PASSWORD)
                    printf '%s' "${a%%=*}=***"
                    return 0
                ;;
            esac
        ;;

    esac

    printf '%s' "${a}"

}
run () {

    [[ $# -gt 0 ]] || die "Error: run requires a command" 2

    if (( VX_VERBOSE )); then
        {
            printf '+'
            local a=""

            for a in "$@"; do
                printf ' %q' "$(redact_arg "${a}")"
            done

            printf '\n'
        } >&2
    fi

    "$@"
    return $?

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
    [[ -n "${p}" ]] || { printf ''; return 0; }

    p="${p/#\~/${HOME}}"
    printf '%s' "${p}"

}
is_ci () {

    [[ "${CI:-}" =~ ^(1|true|yes)$ ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]

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

    if [[ "$(uname -s 2>/dev/null || true)" =~ ^(MINGW|MSYS|CYGWIN) ]] && has_cmd explorer.exe; then
        if has_cmd cygpath; then
            explorer.exe "$(cygpath -w "${path}")" >/dev/null 2>&1 || true
        else
            explorer.exe "${path}" >/dev/null 2>&1 || true
        fi
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
with_sudo () {

    local uid=""

    uid="${EUID:-}"
    [[ -n "${uid}" ]] || uid="$(id -u 2>/dev/null || echo 1)"

    if [[ "${uid}" -eq 0 ]]; then
        "$@"
        return $?
    fi

    case "$(uname -s 2>/dev/null || true)" in
        MINGW*|MSYS*|CYGWIN*) "$@"; return $? ;;
    esac
    [[ "${OS:-}" == "Windows_NT" ]] && { "$@"; return $?; }

    if has_cmd sudo; then
        sudo "$@"
        return $?
    fi

    if has_cmd doas; then
        doas "$@"
        return $?
    fi

    die "Need root privileges (sudo/doas not found). Run as root or install sudo/doas." 2

}
detect_pkg_mgr () {

    case "$(uname -s 2>/dev/null || true)" in
        Darwin)
            has_cmd brew && { echo brew; return 0; }
        ;;
        MINGW*|MSYS*|CYGWIN*)
            has_cmd winget && { echo winget; return 0; }
            has_cmd choco  && { echo choco;  return 0; }
            echo ""
            return 1
        ;;
    esac
    [[ "${OS:-}" == "Windows_NT" ]] && {

        has_cmd winget && { echo winget; return 0; }
        has_cmd choco  && { echo choco;  return 0; }
        echo ""
        return 1

    }

    if has_cmd apt-get; then echo apt; return 0; fi
    if has_cmd dnf; then echo dnf; return 0; fi
    if has_cmd yum; then echo yum; return 0; fi
    if has_cmd pacman; then echo pacman; return 0; fi
    if has_cmd zypper; then echo zypper; return 0; fi
    if has_cmd apk; then echo apk; return 0; fi

    echo ""
    return 1

}
install_pkg () {

    local manager="${1}"
    local do_update="${2}"

    shift 2
    [[ $# -gt 0 ]] || return 0

    case "${manager}" in
        apt)
            if (( do_update )); then
                DEBIAN_FRONTEND=noninteractive with_sudo apt-get update
            fi

            DEBIAN_FRONTEND=noninteractive with_sudo apt-get install -y "$@"
        ;;
        dnf)
            if (( do_update )); then
                with_sudo dnf makecache -y || true
            fi

            with_sudo dnf install -y "$@"
        ;;
        yum)
            if (( do_update )); then
                with_sudo yum makecache -y || true
            fi

            with_sudo yum install -y "$@"
        ;;
        pacman)
            if (( do_update )); then
                with_sudo pacman -Syu --noconfirm --needed "$@"
            else
                with_sudo pacman -S --noconfirm --needed "$@"
            fi
        ;;
        zypper)
            if (( do_update )); then
                with_sudo zypper --non-interactive refresh || true
            fi

            with_sudo zypper --non-interactive install -y "$@"
        ;;
        apk)
            with_sudo apk add --no-cache "$@"
        ;;
        brew)
            need_cmd brew

            if (( do_update )); then
                brew update >/dev/null 2>&1 || true
                brew install "$@"
            else
                HOMEBREW_NO_AUTO_UPDATE=1 brew install "$@"
            fi
        ;;
        winget)
            local p=""
            for p in "$@"; do
                run winget install --id "${p}" -e --accept-package-agreements --accept-source-agreements --silent
            done
        ;;
        choco)
            local p=""
            for p in "$@"; do
                run choco install -y "${p}"
            done
        ;;
        *)
            die "Unsupported package manager: ${manager}" 2
        ;;
    esac

}
dedupe_inplace () {

    local name="${1:-}"
    [[ -n "${name}" ]] || return 0

    [[ "${name}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || die "Invalid array name: ${name}" 2

    local -a in=()
    eval "in=(\"\${${name}[@]}\")"

    local -a out=()
    local x="" y="" found=0

    for x in "${in[@]}"; do

        [[ -n "${x}" ]] || continue

        found=0
        for y in "${out[@]}"; do
            if [[ "${y}" == "${x}" ]]; then
                found=1
                break
            fi
        done

        (( found )) && continue
        out+=( "${x}" )

    done

    local assign=""
    for x in "${out[@]}"; do
        assign+=" $(printf '%q' "${x}")"
    done

    eval "${name}=(${assign# })"

}
win_try_add_paths () {

    local -a candidates=(
        "/c/Program Files/Git/usr/bin"
        "/c/Program Files/Git/bin"
        "/c/Program Files (x86)/Git/usr/bin"
        "/c/Program Files (x86)/Git/bin"
        "/c/ProgramData/chocolatey/bin"
        "/c/Windows/System32"
        "/c/Windows"
    )

    local p=""
    for p in "${candidates[@]}"; do

        [[ -d "${p}" ]] || continue

        case ":${PATH}:" in
            *":${p}:"*) ;;
            *) export PATH="${p}:${PATH}" ;;
        esac

    done

}
ensure_pkg () {

    local do_update=1

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --no-update) do_update=0; shift ;;
            --) shift; break ;;
            -*) die "Unknown option: ${1}" 2 ;;
            *) break ;;
        esac
    done

    local -a tools=( "$@" )
    [[ ${#tools[@]} -gt 0 ]] || tools=( jq perl grep curl )

    local uname_s os
    uname_s="$(uname -s 2>/dev/null || true)"

    case "${uname_s}" in
        Linux) os="linux" ;;
        Darwin) os="mac" ;;
        MINGW*|MSYS*|CYGWIN*) os="win" ;;
        *) [[ "${OS:-}" == "Windows_NT" ]] && os="win" || return 0 ;;
    esac

    if [[ "${os}" == "linux" || "${os}" == "mac" ]]; then

        local mgr=""

        if [[ "${os}" == "linux" ]]; then

            mgr="$(detect_pkg_mgr || true)"

            [[ -n "${mgr}" ]] || {
                has_cmd zypper && mgr="zypper"
                has_cmd apk && mgr="apk"
            }

            [[ -n "${mgr}" ]] || die "No supported package manager found (apt/dnf/yum/pacman/zypper/apk)." 2

        else

            has_cmd brew || die "Homebrew is required on macOS. Install brew then retry." 2
            mgr="brew"

        fi

        local -a pkgs=()
        local t="" pkg=""

        for t in "${tools[@]}"; do

            has_cmd "${t}" && continue

            pkg="${t}"

            case "${t}" in
                awk) pkg="gawk" ;;
            esac

            if [[ "${os}" == "linux" ]]; then
                case "${t}" in
                    head|tail|wc|sort) pkg="coreutils" ;;
                    find|xargs)        pkg="findutils" ;;
                esac

                # LLVM / Clang mapping (bindgen / clang-sys / spellcheck)
                case "${t}" in
                    llvm-dev|llvm|llvm-devel)
                        case "${mgr}" in
                            apt)     pkg="llvm-dev" ;;
                            dnf|yum) pkg="llvm-devel" ;;
                            zypper)  pkg="llvm-devel" ;;
                            pacman)  pkg="llvm" ;;
                            apk)     pkg="llvm-dev" ;;
                            *)       pkg="llvm" ;;
                        esac
                    ;;
                    libclang-dev|libclang|libclang-devel)
                        case "${mgr}" in
                            apt)     pkg="libclang-dev" ;;
                            dnf|yum) pkg="libclang-devel" ;;
                            zypper)  pkg="libclang-devel" ;;
                            pacman)  pkg="libclang" ;;
                            apk)     pkg="clang-dev" ;;
                            *)       pkg="libclang-dev" ;;
                        esac
                    ;;
                esac

            else

                # macOS: bindgen wants libclang, best source is brew llvm
                case "${t}" in
                    clang|llvm-dev|llvm|libclang-dev|libclang)
                        pkg="llvm"
                    ;;
                    gawk) pkg="gawk" ;;
                esac

            fi

            pkgs+=( "${pkg}" )

        done

        if [[ "${os}" == "linux" ]]; then
            has_cmd update-ca-certificates || pkgs+=( "ca-certificates" )
        fi

        dedupe_inplace pkgs
        [[ ${#pkgs[@]} -eq 0 ]] && return 0

        run install_pkg "${mgr}" "${do_update}" "${pkgs[@]}"
        return 0

    fi

    local -a w_ids=()
    local -a c_pkgs=()
    local need_git=0
    local t=""

    for t in "${tools[@]}"; do

        has_cmd "${t}" && continue

        case "${t}" in
            jq)
                w_ids+=( "jqlang.jq" )
                c_pkgs+=( "jq" )
            ;;
            hunspell)
                c_pkgs+=( "hunspell.portable" )
            ;;
            *)
                need_git=1
            ;;
        esac

    done

    if (( need_git )); then
        w_ids+=( "Git.Git" )
        c_pkgs+=( "git" )
    fi

    dedupe_inplace w_ids
    dedupe_inplace c_pkgs

    if has_cmd winget && (( ${#w_ids[@]} > 0 )); then
        run install_pkg "winget" 0 "${w_ids[@]}"
        win_try_add_paths
    fi
    if has_cmd choco && (( ${#c_pkgs[@]} > 0 )); then
        run install_pkg "choco" 0 "${c_pkgs[@]}"
        win_try_add_paths
    fi
    if ! has_cmd winget && ! has_cmd choco; then
        log "Windows detected, but neither winget nor choco found."
        log "Install one of them, or install Git for Windows and retry."
        return 0
    fi
    if (( need_git )); then
        has_cmd git || log "Note: Git installed but not visible yet. Restart shell to refresh PATH."
    fi

    return 0

}
need_file () {

    local path=""
    path="$(path_expand "${1:-}")"
    [[ -f "${path}" ]] || die "Missing file: ${path}" 2

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
        source "${file}" || die "Failed to source: ${file}" 2

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
            doc_render
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
