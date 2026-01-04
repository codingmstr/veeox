#!/usr/bin/env bash
set -Eeuo pipefail

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { echo "This file must be sourced, not executed." >&2; exit 2; }
[[ -n "${BASE_SH_LOADED:-}" ]] && return 0
BASE_SH_LOADED=1

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
declare -ar SKIP_MODULES=("base" "run" "install")

IFS=$'\n\t'
YES_ENV="${YES_ENV:-0}"
QUIET_ENV="${QUIET_ENV:-0}"
VERBOSE_ENV="${VERBOSE_ENV:-0}"

cd_root () {

    cd -- "${ROOT_DIR}"

}
log () {

    (( QUIET_ENV )) && return 0
    printf '%s\n' "$@"

}
elog () {

    printf '%s\n' "$@" >&2

}
die () {

    local msg="${1:-}"
    local code="${2:-1}"

    elog "${msg}"

    if [[ $- == *i* ]]; then
        return "${code}"
    fi

    exit "${code}"

}
confirm () {

    local msg="${1:-Continue?}"

    (( YES_ENV )) && return 0
    is_ci && die "Refusing interactive prompt in CI." 2

    local ans=""
    local tty="/dev/tty"

    if [[ -r "${tty}" && -w "${tty}" ]]; then

        printf '%s' "${msg} [y/N]: " > "${tty}"
        IFS= read -r ans < "${tty}" 2>/dev/null || true

    else

        [[ -t 0 ]] || die "Non-interactive: set YES_ENV=1 to bypass prompts." 2

        printf '%s' "${msg} [y/N]: " >&2
        IFS= read -r ans 2>/dev/null || true

    fi

    [[ "${ans}" == "y" || "${ans}" == "Y" || "${ans}" == "yes" || "${ans}" == "Yes" || "${ans}" == "YES" ]]

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

    if (( VERBOSE_ENV )); then
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
has () {

    command -v "${1}" >/dev/null 2>&1

}
is_ci () {

    local v=""

    v="${CI:-}"
    [[ "${v}" =~ ^(1|true|yes)$ ]] && return 0

    [[ -n "${GITHUB_ACTIONS:-}" ]] && return 0
    [[ -n "${GITLAB_CI:-}" ]] && return 0
    [[ -n "${BUILDKITE:-}" ]] && return 0
    [[ -n "${CIRCLECI:-}" ]] && return 0
    [[ -n "${TRAVIS:-}" ]] && return 0
    [[ -n "${TF_BUILD:-}" ]] && return 0
    [[ -n "${JENKINS_URL:-}" ]] && return 0

    return 1

}
is_wsl () {

    [[ -n "${WSL_DISTRO_NAME:-}" ]] && return 0

    grep -qi microsoft /proc/version 2>/dev/null && return 0
    grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null && return 0

    return 1

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
path_expand () {

    local p="${1:-}"
    [[ -n "${p}" ]] || { printf ''; return 0; }

    if [[ "${p}" == "~" ]]; then
        [[ -n "${HOME:-}" ]] || die "HOME not set; cannot expand ~" 2
        p="${HOME}"
    elif [[ "${p}" == "~/"* ]]; then
        [[ -n "${HOME:-}" ]] || die "HOME not set; cannot expand ~/" 2
        p="${HOME}/${p#\~/}"
    fi

    printf '%s' "${p}"

}
open_path () {

    local path=""
    path="$(path_expand "${1:-}")"
    [[ -n "${path}" ]] || die "Error: open_path requires a path" 2

    is_ci && die "Refusing to open browser in CI." 2

    if has wslview; then
        wslview "${path}" >/dev/null 2>&1 || true
        return 0
    fi
    if is_wsl && has wslpath && has explorer.exe; then
        explorer.exe "$(wslpath -w "${path}")" >/dev/null 2>&1 || true
        return 0
    fi
    if [[ "$(uname -s 2>/dev/null || true)" =~ ^(MINGW|MSYS|CYGWIN) ]] && has explorer.exe; then
        if has cygpath; then
            explorer.exe "$(cygpath -w "${path}")" >/dev/null 2>&1 || true
        else
            explorer.exe "${path}" >/dev/null 2>&1 || true
        fi
        return 0
    fi
    if has xdg-open; then
        xdg-open "${path}" >/dev/null 2>&1 || true
        return 0
    fi
    if has open; then
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

    elog "Error: ${src}:${line}"

    if (( VERBOSE_ENV )); then

        if [[ "${cmd}" == *x-access-token:*@* ]]; then
            local pre="${cmd%%x-access-token:*}x-access-token:"
            local rest="${cmd#*x-access-token:}"
            local after="${rest#*@}"
            cmd="${pre}***@${after}"
        fi

        elog "Command: ${cmd}"

    fi
    if [[ $- == *i* ]]; then
        return "${ec}"
    fi

    exit "${ec}"

}
abs_dir () {

    local p="${1:-}"
    [[ -n "${p}" ]] || die "abs_dir: missing path" 2
    ( cd -- "${p}" >/dev/null 2>&1 && pwd ) || die "abs_dir: can't cd: ${p}" 2

}
detect_os () {

    local u=""
    u="$(uname -s 2>/dev/null || echo unknown)"

    case "${u}" in
        Linux)  echo linux ;;
        Darwin) echo mac ;;
        MINGW*|MSYS*|CYGWIN*) echo win ;;
        *) echo unknown ;;
    esac

}
uc_first () {

    local s="${1:-}"
    [[ -n "${s}" ]] || { printf '%s' ""; return 0; }

    printf '%s%s' "$(printf '%s' "${s:0:1}" | tr '[:lower:]' '[:upper:]')" "${s:1}"

}
mkdir_p () {

    mkdir -p -- "$@" 2>/dev/null || mkdir -p "$@"

}
ln_sf () {

    ln -sf -- "${1}" "${2}" 2>/dev/null || ln -sf "${1}" "${2}"

}
dir_exists () {

    local path=""
    path="$(path_expand "${1:-}")"
    [[ -n "${path}" ]] || return 1
    [[ -d "${path}" ]]

}
file_exists () {

    local path=""
    path="$(path_expand "${1:-}")"
    [[ -n "${path}" ]] || return 1
    [[ -f "${path}" ]]

}
ensure_dir () {

    local path="" mode="" owner="" group="" strict=0

    path="$(path_expand "${1:-}")"
    [[ -n "${path}" ]] || die "ensure_dir: missing path" 2

    mode="${2:-}"
    owner="${3:-}"
    group="${4:-}"
    strict="${5:-0}"

    if [[ -e "${path}" && ! -d "${path}" ]]; then
        die "ensure_dir: path exists but not a directory: ${path}" 2
    fi

    [[ -d "${path}" ]] || mkdir_p "${path}" || die "ensure_dir: failed to create dir: ${path}" 2

    if [[ -n "${mode}" ]]; then
        if has chmod; then
            chmod "${mode}" "${path}" 2>/dev/null || {
                if (( strict )); then
                    die "ensure_dir: chmod failed for ${path}" 2
                    return $?
                fi
                true
            }
        else
            (( strict )) && die "ensure_dir: chmod not available for ${path}" 2
        fi
    fi

    if [[ -n "${owner}" ]]; then
        if has chown; then
            if [[ -n "${group}" ]]; then
                chown "${owner}:${group}" "${path}" 2>/dev/null || {
                    if (( strict )); then
                        die "ensure_dir: chown failed for ${path}" 2
                        return $?
                    fi
                    true
                }
            else
                chown "${owner}" "${path}" 2>/dev/null || {
                    if (( strict )); then
                        die "ensure_dir: chown failed for ${path}" 2
                        return $?
                    fi
                    true
                }
            fi
        else
            (( strict )) && die "ensure_dir: chown not available for ${path}" 2
        fi
    fi

    [[ -d "${path}" ]] || die "ensure_dir: directory still missing after create: ${path}" 2

}
ensure_file () {

    local path="" mode="" owner="" group="" strict=0

    path="$(path_expand "${1:-}")"
    [[ -n "${path}" ]] || die "ensure_file: missing path" 2

    mode="${2:-}"
    owner="${3:-}"
    group="${4:-}"
    strict="${5:-0}"

    if [[ -e "${path}" && ! -f "${path}" ]]; then
        die "ensure_file: path exists but not a regular file: ${path}" 2
    fi
    if [[ ! -f "${path}" ]]; then

        ensure_dir "$(dirname -- "${path}")" "" "" "" "${strict}"

        : > "${path}" 2>/dev/null || die "ensure_file: failed to create file: ${path}" 2

    fi
    if [[ -n "${mode}" ]]; then
        if has chmod; then
            chmod "${mode}" "${path}" 2>/dev/null || {
                if (( strict )); then
                    die "ensure_file: chmod failed for ${path}" 2
                    return $?
                fi
                true
            }
        else
            (( strict )) && die "ensure_file: chmod not available for ${path}" 2
        fi
    fi
    if [[ -n "${owner}" ]]; then
        if has chown; then
            if [[ -n "${group}" ]]; then
                chown "${owner}:${group}" "${path}" 2>/dev/null || {
                    if (( strict )); then
                        die "ensure_file: chown failed for ${path}" 2
                        return $?
                    fi
                    true
                }
            else
                chown "${owner}" "${path}" 2>/dev/null || {
                    if (( strict )); then
                        die "ensure_file: chown failed for ${path}" 2
                        return $?
                    fi
                    true
                }
            fi
        else
            (( strict )) && die "ensure_file: chown not available for ${path}" 2
        fi
    fi

    [[ -f "${path}" ]] || die "ensure_file: file still missing after create: ${path}" 2

}
ensure_linux_pkg () {

    local -a wants=( "$@" )
    (( ${#wants[@]} )) || die "ensure_linux_pkg: missing package name(s)" 2

    local mgr=""

    if has apt-get; then
        mgr="apt"
    elif has dnf; then
        mgr="dnf"
    elif has yum; then
        mgr="yum"
    elif has pacman; then
        mgr="pacman"
    elif has zypper; then
        mgr="zypper"
    elif has apk; then
        mgr="apk"
    fi

    [[ -n "${mgr}" ]] || die "Linux: no supported package manager found (apt/dnf/yum/pacman/zypper/apk)." 2

    local -a sudo_cmd=()
    local uid=""
    uid="${EUID:-}"
    [[ -n "${uid}" ]] || uid="$(id -u 2>/dev/null || echo 1)"

    if [[ "${uid}" -ne 0 ]]; then

        if has sudo; then
            if is_ci; then
                sudo -n true >/dev/null 2>&1 || die "Linux: need root privileges (sudo requires password in CI)." 2
                sudo_cmd=( sudo -n )
            else
                sudo_cmd=( sudo )
            fi
        elif has doas; then
            if is_ci; then
                doas -n true >/dev/null 2>&1 || die "Linux: need root privileges (doas requires password in CI)." 2
                sudo_cmd=( doas -n )
            else
                sudo_cmd=( doas )
            fi
        else
            die "Linux: need root privileges (sudo/doas not found)." 2
        fi

    fi

    local is_gnu_prefer=0
    local want=""
    local ver=""

    local -a need_pkgs=()
    local -a check_want=()
    local -a check_mode=()
    local -a check_pkg=()
    local -a prefer_gnu=()

    local pkg_installed=0

    for want in "${wants[@]}"; do

        [[ -n "${want}" ]] || continue

        local pkg="${want}"
        local mode="cmd"

        case "${want}" in
            llvm-dev|llvm-devel|llvm-config|libclang-dev|libclang-devel)
                mode="pkg"
            ;;
        esac

        is_gnu_prefer=0
        case "${want}" in
            sed|grep|awk|find|xargs|head|tail|sort|wc|chmod|mkdir)
                is_gnu_prefer=1
            ;;
        esac

        (( is_gnu_prefer )) && prefer_gnu+=( "${want}" )

        case "${want}" in
            jq)       pkg="jq" ;;
            perl)     pkg="perl" ;;
            grep)     pkg="grep" ;;
            curl)     pkg="curl" ;;
            git)      pkg="git" ;;
            hunspell) pkg="hunspell" ;;
            bash)     pkg="bash" ;;
            awk)
                pkg="gawk"
                mode="cmd"
            ;;
            sed)      pkg="sed" ;;
            head|tail|sort|wc|chmod|mkdir)
                      pkg="coreutils" ;;
            find|xargs)
                      pkg="findutils" ;;

            clang)
                pkg="clang"
                mode="cmd"
            ;;
            llvm-dev|llvm-devel|llvm-config)
                case "${mgr}" in
                    apt)     pkg="llvm-dev" ;;
                    dnf|yum) pkg="llvm-devel" ;;
                    zypper)  pkg="llvm-devel" ;;
                    pacman)  pkg="llvm" ;;
                    apk)     pkg="llvm-dev" ;;
                esac
                mode="pkg"
            ;;
            libclang-dev|libclang-devel)
                case "${mgr}" in
                    apt)     pkg="libclang-dev" ;;
                    dnf|yum) pkg="libclang-devel" ;;
                    zypper)  pkg="libclang-devel" ;;
                    pacman)  pkg="libclang" ;;
                    apk)     pkg="clang-dev" ;;
                esac
                mode="pkg"
            ;;
            *)
                :
            ;;
        esac

        if [[ "${mode}" == "cmd" ]]; then

            if has "${want}"; then

                if (( is_gnu_prefer )); then

                    ver="$("${want}" --version 2>/dev/null || true)"
                    case "${ver}" in
                        *GNU*|*"Free Software Foundation"*|*coreutils*|*findutils*|*gawk*|*GNU\ Awk* )
                            continue
                        ;;
                        *)
                            :
                        ;;
                    esac

                else
                    continue
                fi

            fi

        else

            pkg_installed=0
            case "${mgr}" in
                apt)     dpkg -s "${pkg}" >/dev/null 2>&1 && pkg_installed=1 ;;
                dnf|yum) rpm  -q "${pkg}" >/dev/null 2>&1 && pkg_installed=1 ;;
                zypper)  rpm  -q "${pkg}" >/dev/null 2>&1 && pkg_installed=1 ;;
                pacman)  pacman -Qi "${pkg}" >/dev/null 2>&1 && pkg_installed=1 ;;
                apk)     apk info -e "${pkg}" >/dev/null 2>&1 && pkg_installed=1 ;;
            esac

            (( pkg_installed )) && continue

        fi

        need_pkgs+=( "${pkg}" )
        check_want+=( "${want}" )
        check_mode+=( "${mode}" )
        check_pkg+=( "${pkg}" )

    done

    if (( ${#need_pkgs[@]} == 0 )); then
        return 0
    fi

    local -a uniq_pkgs=()
    local i=0 j=0 seen=0

    for i in "${need_pkgs[@]}"; do

        [[ -n "${i}" ]] || continue

        seen=0
        for j in "${uniq_pkgs[@]-}"; do
            if [[ "${j}" == "${i}" ]]; then
                seen=1
                break
            fi
        done

        (( seen )) || uniq_pkgs+=( "${i}" )

    done

    log "Linux: installing packages via ${mgr}: ${uniq_pkgs[*]}"

    case "${mgr}" in
        apt)
            if [[ "${APT_UPDATED_ENV:-0}" -ne 1 ]]; then

                local n=0
                while :; do

                    n=$(( n + 1 ))

                    "${sudo_cmd[@]}" env \
                        DEBIAN_FRONTEND=noninteractive \
                        APT_LISTCHANGES_FRONTEND=none \
                        apt-get -o Acquire::Retries=3 -o Dpkg::Use-Pty=0 update && break

                    (( n >= 3 )) && die "Linux(apt): apt-get update failed after retries." 2
                    sleep 2

                done

                APT_UPDATED_ENV=1
            fi

            local m=0
            while :; do

                m=$(( m + 1 ))

                "${sudo_cmd[@]}" env \
                    DEBIAN_FRONTEND=noninteractive \
                    APT_LISTCHANGES_FRONTEND=none \
                    apt-get -o Acquire::Retries=3 -o Dpkg::Use-Pty=0 \
                    -o Dpkg::Options::=--force-confdef \
                    -o Dpkg::Options::=--force-confold \
                    install -y --no-install-recommends "${uniq_pkgs[@]}" && break

                (( m >= 3 )) && die "Linux(apt): apt-get install failed after retries: ${uniq_pkgs[*]}" 2
                sleep 2

            done
        ;;
        dnf)
            [[ "${DNF_CACHED_ENV:-0}" -eq 1 ]] || { "${sudo_cmd[@]}" dnf makecache -y >/dev/null 2>&1 || true; DNF_CACHED_ENV=1; }
            "${sudo_cmd[@]}" dnf install -y "${uniq_pkgs[@]}"
        ;;
        yum)
            [[ "${YUM_CACHED_ENV:-0}" -eq 1 ]] || { "${sudo_cmd[@]}" yum makecache -y >/dev/null 2>&1 || true; YUM_CACHED_ENV=1; }
            "${sudo_cmd[@]}" yum install -y "${uniq_pkgs[@]}"
        ;;
        pacman)
            "${sudo_cmd[@]}" pacman -Syu --noconfirm --needed "${uniq_pkgs[@]}"
        ;;
        zypper)
            "${sudo_cmd[@]}" zypper --non-interactive refresh >/dev/null 2>&1 || true
            "${sudo_cmd[@]}" zypper --non-interactive install --auto-agree-with-licenses "${uniq_pkgs[@]}"
        ;;
        apk)
            "${sudo_cmd[@]}" apk add --no-cache "${uniq_pkgs[@]}"
        ;;
    esac

    hash -r 2>/dev/null || true

    local k=0
    for (( k = 0; k < ${#check_want[@]}; k++ )); do

        want="${check_want[$k]}"
        local mode="${check_mode[$k]}"
        local pkg="${check_pkg[$k]}"

        if [[ "${mode}" == "cmd" ]]; then
            has "${want}" || die "Linux: failed to provide command '${want}' (installed '${pkg}' but command still missing)." 2
        else

            pkg_installed=0
            case "${mgr}" in
                apt)     dpkg -s "${pkg}" >/dev/null 2>&1 && pkg_installed=1 ;;
                dnf|yum) rpm  -q "${pkg}" >/dev/null 2>&1 && pkg_installed=1 ;;
                zypper)  rpm  -q "${pkg}" >/dev/null 2>&1 && pkg_installed=1 ;;
                pacman)  pacman -Qi "${pkg}" >/dev/null 2>&1 && pkg_installed=1 ;;
                apk)     apk info -e "${pkg}" >/dev/null 2>&1 && pkg_installed=1 ;;
            esac

            (( pkg_installed )) || die "Linux: failed to install package '${pkg}' for '${want}'." 2

        fi

    done

}
ensure_mac_pkg () {

    local -a wants=( "$@" )
    (( ${#wants[@]} )) || die "ensure_mac_pkg: missing package name(s)" 2

    has brew || die "macOS: Homebrew is required. Install brew then retry." 2

    local -a need_pkgs=()
    local -a link_alt=()
    local -a link_name=()
    local -a check_want=()

    local want=""
    local gnu_prefer=0

    for want in "${wants[@]}"; do

        [[ -n "${want}" ]] || continue

        local pkg="${want}"
        local alt=""
        local link=""

        gnu_prefer=0
        case "${want}" in
            sed|grep|awk|find|xargs|head|tail|sort|wc|chmod|mkdir)
                gnu_prefer=1
            ;;
        esac

        case "${want}" in
            jq)       pkg="jq" ;;
            perl)     pkg="perl" ;;
            curl)     pkg="curl" ;;
            git)      pkg="git" ;;
            hunspell) pkg="hunspell" ;;
            bash)     pkg="bash" ;;

            awk)      pkg="gawk" ;     alt="gawk" ;     link="awk" ;;
            sed)      pkg="gnu-sed" ;  alt="gsed" ;     link="sed" ;;
            grep)     pkg="grep" ;     alt="ggrep" ;    link="grep" ;;
            find)     pkg="findutils" ;alt="gfind" ;    link="find" ;;
            xargs)    pkg="findutils" ;alt="gxargs" ;   link="xargs" ;;

            head)     pkg="coreutils" ;alt="ghead" ;    link="head" ;;
            tail)     pkg="coreutils" ;alt="gtail" ;    link="tail" ;;
            sort)     pkg="coreutils" ;alt="gsort" ;    link="sort" ;;
            wc)       pkg="coreutils" ;alt="gwc" ;      link="wc" ;;
            chmod)    pkg="coreutils" ;alt="gchmod" ;   link="chmod" ;;
            mkdir)    pkg="coreutils" ;alt="gmkdir" ;   link="mkdir" ;;

            clang|llvm-dev|llvm-devel|llvm-config|libclang-dev|libclang-devel)
                pkg="llvm"
            ;;

            *)
                :
            ;;
        esac

        if [[ "${want}" == "clang" || "${want}" == "llvm-dev" || "${want}" == "llvm-devel" || "${want}" == "llvm-config" || "${want}" == "libclang-dev" || "${want}" == "libclang-devel" ]]; then
            brew list --versions llvm >/dev/null 2>&1 && { check_want+=( "${want}" ); continue; }
        fi

        if (( gnu_prefer )); then

            if [[ -n "${link}" ]]; then

                if [[ "$(command -v "${want}" 2>/dev/null || true)" == "${HOME}/.local/bin/${want}" ]]; then
                    has "${alt}" && { check_want+=( "${want}" ); continue; }
                fi

            fi

        else

            has "${want}" && { check_want+=( "${want}" ); continue; }

        fi

        need_pkgs+=( "${pkg}" )
        check_want+=( "${want}" )

        if [[ -n "${alt}" && -n "${link}" ]]; then
            link_alt+=( "${alt}" )
            link_name+=( "${link}" )
        fi

    done

    if (( ${#need_pkgs[@]} )); then

        local -a uniq_pkgs=()
        local i=0 j=0 seen=0

        for i in "${need_pkgs[@]}"; do

            [[ -n "${i}" ]] || continue

            seen=0
            for j in "${uniq_pkgs[@]-}"; do
                if [[ "${j}" == "${i}" ]]; then
                    seen=1
                    break
                fi
            done

            (( seen )) || uniq_pkgs+=( "${i}" )

        done

        log "macOS: installing via brew: ${uniq_pkgs[*]}"

        if is_ci; then
            HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install "${uniq_pkgs[@]}"
        else
            brew install "${uniq_pkgs[@]}"
        fi

    fi

    if (( ${#link_alt[@]} )); then

        mkdir_p "${HOME}/.local/bin" 2>/dev/null || true

        local x=0
        for (( x = 0; x < ${#link_alt[@]}; x++ )); do

            local alt="${link_alt[$x]}"
            local link="${link_name[$x]}"

            has "${alt}" || die "macOS: installed but '${alt}' not found." 2
            ln_sf "$(command -v "${alt}")" "${HOME}/.local/bin/${link}" 2>/dev/null || true

        done

        case ":${PATH}:" in
            *":${HOME}/.local/bin:"*) ;;
            *) export PATH="${HOME}/.local/bin:${PATH}" ;;
        esac

    fi

    if brew list --versions llvm >/dev/null 2>&1; then

        local llvm_prefix=""
        llvm_prefix="$(brew --prefix llvm 2>/dev/null || true)"
        if [[ -n "${llvm_prefix}" ]]; then
            case ":${PATH}:" in
                *":${llvm_prefix}/bin:"*) ;;
                *) export PATH="${llvm_prefix}/bin:${PATH}" ;;
            esac
        fi

    fi

    hash -r 2>/dev/null || true

    local w=""
    for w in "${check_want[@]}"; do

        case "${w}" in
            clang|llvm-dev|llvm-devel|llvm-config|libclang-dev|libclang-devel)
                brew list --versions llvm >/dev/null 2>&1 || die "macOS: failed to install 'llvm' for '${w}'." 2
            ;;
            *)
                has "${w}" || die "macOS: failed to provide command '${w}'." 2
            ;;
        esac

    done

}
ensure_win_pkg () {

    local -a wants=( "$@" )
    (( ${#wants[@]} )) || die "ensure_win_pkg: missing package name(s)" 2

    is_wsl && die "WSL detected: use ensure_linux_pkg instead of ensure_win_pkg." 2

    local has_winget=0
    local has_choco=0

    has winget && has_winget=1
    has choco  && has_choco=1

    local -a winget_ids=()
    local -a choco_pkgs=()
    local need_git=0

    local want=""
    for want in "${wants[@]}"; do

        [[ -n "${want}" ]] || continue
        has "${want}" && continue

        local winget_id=""
        local choco_pkg=""

        case "${want}" in
            jq)
                winget_id="jqlang.jq"
                (( has_winget )) || choco_pkg="jq"
            ;;
            git|bash|grep|perl|sed|awk|find|xargs|sort|head|tail|wc|chmod|mkdir|curl)
                need_git=1
            ;;
            clang|llvm-dev|llvm-devel|llvm-config|libclang-dev|libclang-devel)
                winget_id="LLVM.LLVM"
                (( has_winget )) || choco_pkg="llvm"
            ;;
            hunspell)
                winget_id="FSFhu.Hunspell"
                (( has_winget )) || choco_pkg="hunspell.portable"
            ;;
            *)
                :
            ;;
        esac

        [[ -n "${winget_id}" ]] && winget_ids+=( "${winget_id}" )
        [[ -n "${choco_pkg}" ]] && choco_pkgs+=( "${choco_pkg}" )

    done

    if (( need_git )); then
        winget_ids+=( "Git.Git" )
        (( has_winget )) || choco_pkgs+=( "git" )
    fi

    local -a uniq_winget=()
    local -a uniq_choco=()
    local i="" j="" seen=0

    for i in "${winget_ids[@]-}"; do

        [[ -n "${i}" ]] || continue

        seen=0
        for j in "${uniq_winget[@]-}"; do
            if [[ "${j}" == "${i}" ]]; then
                seen=1
                break
            fi
        done
        (( seen )) || uniq_winget+=( "${i}" )

    done

    for i in "${choco_pkgs[@]-}"; do

        [[ -n "${i}" ]] || continue

        seen=0
        for j in "${uniq_choco[@]-}"; do
            if [[ "${j}" == "${i}" ]]; then
                seen=1
                break
            fi
        done
        (( seen )) || uniq_choco+=( "${i}" )

    done

    if (( ${#uniq_winget[@]} == 0 && ${#uniq_choco[@]} == 0 )); then
        return 0
    fi

    local did_any=0

    if (( has_winget )) && (( ${#uniq_winget[@]} )); then
        local id=""
        for id in "${uniq_winget[@]}"; do
            log "Windows: installing '${id}' via winget ..."
            winget install --id "${id}" -e \
                --accept-package-agreements --accept-source-agreements --silent --disable-interactivity >/dev/null 2>&1 || true
        done
        did_any=1
    fi

    if (( ${#uniq_choco[@]} )); then
        (( has_choco )) || die "Windows: choco required for: ${uniq_choco[*]}" 2

        log "Windows: installing via choco: ${uniq_choco[*]}"
        choco install -y --no-progress "${uniq_choco[@]}" >/dev/null 2>&1 || true
        did_any=1
    fi

    (( did_any )) || die "Windows: neither winget nor choco available (or no mapping)." 2

    local -a candidates=(
        "/c/Program Files/Git/usr/bin"
        "/c/Program Files/Git/mingw64/bin"
        "/c/Program Files/Git/bin"
        "/c/Program Files (x86)/Git/usr/bin"
        "/c/Program Files (x86)/Git/mingw64/bin"
        "/c/Program Files (x86)/Git/bin"
        "/c/Program Files/LLVM/bin"
        "/c/Program Files (x86)/LLVM/bin"
        "/c/ProgramData/chocolatey/bin"
        "/c/Windows/System32"
        "/c/Windows"
    )

    local p=""
    local prefix=""

    for p in "${candidates[@]}"; do

        [[ -d "${p}" ]] || continue

        case ":${PATH}:" in
            *":${p}:"*) ;;
            *) prefix+="${p}:" ;;
        esac

    done

    [[ -n "${prefix}" ]] && export PATH="${prefix}${PATH}"

    hash -r 2>/dev/null || true

    for want in "${wants[@]}"; do

        [[ -n "${want}" ]] || continue

        case "${want}" in
            llvm-dev|llvm-devel|llvm-config|libclang-dev|libclang-devel)
                continue
            ;;
        esac

        has "${want}" || die "Windows: installed packages but '${want}' is still missing. Restart shell/session to refresh PATH." 2

    done

}
ensure_pkg () {

    local -a wants=( "$@" )
    (( ${#wants[@]} )) || die "ensure_pkg: missing package name(s)" 2

    local os=""
    os="$(detect_os)"

    case "${os}" in
        linux) ensure_linux_pkg "${wants[@]}" ;;
        mac)   ensure_mac_pkg "${wants[@]}" ;;
        win)   ensure_win_pkg "${wants[@]}" ;;
        *)     die "Unsupported OS: ${os}" 2 ;;
    esac

}
should_skip () {

    local s=""
    local name="${1:-}"
    shift || true

    [[ -n "${name}" ]] || return 0
    [[ "${name}" == _* ]] && return 0

    for s in "${SKIP_MODULES[@]-}"; do
        [[ "${name}" == "${s}" ]] && return 0
    done

    for s in "$@"; do
        [[ -n "${s}" ]] || continue
        [[ "${name}" == "${s}" ]] && return 0
    done

    return 1

}
source_loader () {

    local dir="${1:-${SCRIPT_DIR}}"
    shift || true

    [[ -n "${dir}" ]] || { die "source_loader: missing dir" 2; return 2; }
    [[ -d "${dir}" ]] || { die "source_loader: not a dir: ${dir}" 2; return 2; }

    local -a extra_skip=()
    (( $# )) && extra_skip=( "$@" ) || extra_skip=()

    local file=""
    local base=""

    local nullglob_was_set=0
    shopt -q nullglob && nullglob_was_set=1
    shopt -s nullglob

    for file in "${dir}"/*.sh; do

        base="${file##*/}"
        base="${base%.sh}"

        should_skip "${base}" "${extra_skip[@]-}" && continue

        source "${file}" || {

            (( nullglob_was_set )) || shopt -u nullglob
            die "Failed to source: ${file}" 2
            return 2

        }

    done

    (( nullglob_was_set )) || shopt -u nullglob

}
doc_render () {

    local dir="${SCRIPT_DIR}"
    local file="" name="" mod="" fn1="" fn2="" title="" chosen="" printed=0

    printf '%s\n' \
        '' \
        'Usage:' \
        '    vx [--yes] [--quiet] [--verbose] <cmd> [args...]' \
        '' \
        'Global:' \
        '    --yes,    -y     Non-interactive (assume yes)' \
        '    --quiet,  -q     Less output' \
        '    --verbose,-v     Print executed commands'

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

        [[ -n "${chosen}" ]] || continue

        title="${mod//_/ }"
        title="$(uc_first "${title}")"

        printf '\n%s:\n' "${title}"
        "${chosen}" || true

        printed=1

    done

    echo
    (( nullglob_was_set )) || shopt -u nullglob
    (( printed )) || printf '\n(no module help found)\n'

}
parse () {

    CMD="help"
    ARGS=()

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -h|--help)      CMD="help"; shift || true ;;
            --yes|-y)       YES_ENV=1; shift || true ;;
            --quiet|-q)     QUIET_ENV=1; shift || true ;;
            --verbose|-v)   VERBOSE_ENV=1; shift || true ;;
            --)             shift || true; break ;;
            -*)             die "Unknown global flag: ${1}" 2 ;;
            *)              break ;;
        esac
    done

    if [[ $# -gt 0 ]]; then
        CMD="${1}"
        shift || true
        ARGS=( "$@" )
    else
        CMD="help"
        ARGS=()
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
        return 2
    fi

    local fn="cmd_${cmd//-/_}"
    declare -F "${fn}" >/dev/null 2>&1 && { "${fn}" "$@"; return $?; }

    log "Unknown command: ${cmd}"
    log
    doc_render
    return 2

}
boot () {

    local old_trap=""
    old_trap="$(trap -p ERR 2>/dev/null || true)"

    trap on_err ERR

    source_loader || {

        local ec=$?

        if [[ -n "${old_trap}" ]]; then
            eval "${old_trap}"
        else
            trap - ERR
        fi

        return "${ec}"

    }

    parse "$@"

    local ec=0
    if [[ ${ARGS[0]+x} ]]; then
        dispatch "${CMD}" "${ARGS[@]}" || ec=$?
    else
        dispatch "${CMD}" || ec=$?
    fi

    if [[ -n "${old_trap}" ]]; then
        eval "${old_trap}"
    else
        trap - ERR
    fi

    return "${ec}"

}
