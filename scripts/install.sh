#!/usr/bin/env bash
set -Eeuo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/doc.sh"

usage () {

    printf '%s\n' \
        "Usage:" \
        "  ./scripts/install.sh [--yes|-y] [--alias|-a NAME] [--user USER] [--repo REPO] [--name NAME]" \
        "" \
        "Options:" \
        "  -a, --alias NAME   Command name (default: vx)" \
        "      --user  USER   GitHub user (for docs placeholders)" \
        "      --repo  REPO   GitHub repo name (for docs placeholders)" \
        "      --name  NAME   Workspace/crate name (for docs placeholders)" \
        "  -y, --yes          Non-interactive (assume yes)" \
        "  -h, --help         Show help"

}
detect_rc () {

    local shell="${SHELL:-}"
    local os=""
    os="$(detect_os)"

    if [[ -n "${ZSH_VERSION:-}" || "${shell}" == */zsh ]]; then
        printf '%s\n' "${HOME}/.zshrc"
        return 0
    fi
    if [[ -n "${BASH_VERSION:-}" || "${shell}" == */bash ]]; then

        if [[ "${os}" == "mac" ]]; then
            [[ -f "${HOME}/.bashrc" ]] && { printf '%s\n' "${HOME}/.bashrc"; return 0; }
            printf '%s\n' "${HOME}/.bash_profile"
            return 0
        fi
        if [[ "${os}" == "win" ]]; then
            [[ -f "${HOME}/.bash_profile" ]] && { printf '%s\n' "${HOME}/.bash_profile"; return 0; }
            printf '%s\n' "${HOME}/.bashrc"
            return 0
        fi

        printf '%s\n' "${HOME}/.bashrc"
        return 0

    fi
    if [[ "${os}" == "mac" ]]; then
        printf '%s\n' "${HOME}/.zshrc"
        return 0
    fi
    if [[ "${os}" == "win" ]]; then
        [[ -f "${HOME}/.bash_profile" ]] && { printf '%s\n' "${HOME}/.bash_profile"; return 0; }
        printf '%s\n' "${HOME}/.bashrc"
        return 0
    fi

    printf '%s\n' "${HOME}/.bashrc"

}
is_valid_alias () {

    local a="${1:-}"

    [[ -n "${a}" ]] || return 1
    [[ "${a}" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]

}
apply_placeholders () {

    ensure_pkg perl grep find

    local root="${1:-}"
    local alias_name="${2:-vx}"
    local user="${3-}"
    local name="${4-}"
    local repo="${5-}"

    [[ -n "${root}" ]] || return 0
    is_valid_alias "${alias_name}" || return 0

    replace_all "__alias__" "${alias_name}" "${root}" || true

    [[ -n "${user}" ]] && replace_all "__user__" "${user}" "${root}" || true
    [[ -n "${name}" ]] && replace_all "__name__" "${name}" "${root}" || true
    [[ -n "${repo}" ]] && replace_all "__repo__" "${repo}" "${root}" || true

    return 0

}
ensure_line_once () {

    local file="${1:-}"
    local line="${2:-}"

    [[ -n "${file}" ]] || die "ensure_line_once: missing file" 2
    [[ -n "${line}" ]] || die "ensure_line_once: missing line" 2

    touch "${file}" 2>/dev/null || die "Can't write: ${file}" 2
    grep -Fqx -- "${line}" "${file}" 2>/dev/null && return 0

    printf '%s\n' "${line}" >> "${file}" || die "Failed writing: ${file}" 2

}
ensure_path_once () {

    local rc="${1:-}"
    local alias_name="${2:-vx}"

    [[ -n "${rc}" ]] || die "ensure_path_once: missing rc" 2

    touch "${rc}" 2>/dev/null || die "Can't write: ${rc}" 2

    grep -Fqx -- 'export PATH="$HOME/.local/bin:$PATH"' "${rc}" 2>/dev/null && return 0

    printf '\n' >> "${rc}" 2>/dev/null || true
    ensure_line_once "${rc}" "# ${alias_name}"
    ensure_line_once "${rc}" 'export PATH="$HOME/.local/bin:$PATH"'

}
install_launcher () {

    local root="${1:-}"
    local alias_name="${2:-vx}"

    [[ -n "${root}" ]] || die "install_launcher: missing root" 2
    is_valid_alias "${alias_name}" || die "Invalid alias: ${alias_name}" 2

    local run_sh="${root}/scripts/run.sh"
    [[ -f "${run_sh}" ]] || die "Missing: ${run_sh}" 2

    chmod +x "${run_sh}" >/dev/null 2>&1 || true

    local bin_dir="${HOME}/.local/bin"
    mkdir -p -- "${bin_dir}" 2>/dev/null || die "Can't create: ${bin_dir}" 2

    local bin="${bin_dir}/${alias_name}"
    [[ -e "${bin}" ]] && log "Note: overwriting ${bin}"

    if [[ -e "${bin}" ]] && ! (( YES_ENV )); then
        confirm "Overwrite ${bin}?" || die "Canceled." 2
    fi

    local root_q=""
    printf -v root_q '%q' "${root}"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        '' \
        "ROOT=${root_q}" \
        '' \
        'exec bash "${ROOT}/scripts/run.sh" "$@"' \
        > "${bin}" || die "Failed writing: ${bin}" 2

    chmod +x "${bin}" || die "chmod failed: ${bin}" 2
    printf '%s\n' "${bin}"

}
main () {

    ensure_pkg bash grep mkdir chmod

    local alias_name="vx"
    local gh_user=""
    local gh_repo=""
    local proj_name=""

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -h|--help)
                usage
                return 0
            ;;
            -y|--yes)
                YES_ENV=1
                shift || true
            ;;
            -a|--alias)
                shift || true
                alias_name="${1:-}"
                [[ -n "${alias_name}" ]] || die "Missing alias value" 2
                shift || true
            ;;
            --alias=*)
                alias_name="${1#*=}"
                [[ -n "${alias_name}" ]] || die "Missing alias value" 2
                shift || true
            ;;
            --user)
                shift || true
                gh_user="${1:-}"
                [[ -n "${gh_user}" ]] || die "Missing user value" 2
                shift || true
            ;;
            --user=*)
                gh_user="${1#*=}"
                [[ -n "${gh_user}" ]] || die "Missing user value" 2
                shift || true
            ;;
            --repo)
                shift || true
                gh_repo="${1:-}"
                [[ -n "${gh_repo}" ]] || die "Missing repo value" 2
                shift || true
            ;;
            --repo=*)
                gh_repo="${1#*=}"
                [[ -n "${gh_repo}" ]] || die "Missing repo value" 2
                shift || true
            ;;
            --name)
                shift || true
                proj_name="${1:-}"
                [[ -n "${proj_name}" ]] || die "Missing name value" 2
                shift || true
            ;;
            --name=*)
                proj_name="${1#*=}"
                [[ -n "${proj_name}" ]] || die "Missing name value" 2
                shift || true
            ;;
            --)
                shift || true
                break
            ;;
            -*)
                die "Unknown arg: ${1}" 2
            ;;
            *)
                alias_name="${1}"
                shift || true
                break
            ;;
        esac
    done

    is_valid_alias "${alias_name}" || die "Invalid alias: ${alias_name}" 2

    local here="$(abs_dir "$(dirname -- "${BASH_SOURCE[0]}")")"
    local root="$(abs_dir "${here}/..")"

    local bin_path="$(install_launcher "${root}" "${alias_name}")"
    local rc="$(detect_rc)"

    ensure_path_once "${rc}" "${alias_name}"

    apply_placeholders "${root}" "${alias_name}" "${gh_user}" "${proj_name}" "${gh_repo}"

    printf '%s\n' \
        "OK: installed ${bin_path}" \
        "OK: updated ${rc}" \
        "Run: source \"${rc}\"" \
        "Then: ${alias_name} --help"

}

main "$@"
