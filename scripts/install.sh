#!/usr/bin/env bash
set -Eeuo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base.sh"

usage () {

    printf '%s\n' \
        "" \
        "Usage:" \
        "  install.sh [--yes|-y] [--alias|-a NAME] [--user USER] [--repo REPO] [--name NAME]" \
        "" \
        "Options:" \
        "  -a, --alias NAME   Command name (default: vx)" \
        "      --user  USER   GitHub user (for docs placeholders)" \
        "      --repo  REPO   GitHub repo name (for docs placeholders)" \
        "      --name  NAME   Workspace/crate name (for docs placeholders)" \
        "  -y, --yes          Non-interactive (assume yes)" \
        "  -h, --help         Show help" \
        ""

}
need_cmd () {

    local c="${1:-}"
    [[ -n "${c}" ]] || die "need_cmd: missing command" 2
    has "${c}" || die "Missing required command: ${c}" 2

}
home_dir () {

    local h="${HOME:-}"

    if [[ -n "${h}" ]]; then
        printf '%s' "${h}"
        return 0
    fi

    h="$(cd ~ 2>/dev/null && pwd || true)"
    [[ -n "${h}" ]] || die "HOME not set; cannot resolve home directory." 2

    printf '%s' "${h}"

}
ensure_line_once () {

    local file="${1:-}"
    local line="${2:-}"

    [[ -n "${file}" ]] || die "ensure_line_once: missing file" 2
    [[ -n "${line}" ]] || die "ensure_line_once: missing line" 2

    [[ -L "${file}" ]] && die "Refusing to modify symlink: ${file}" 2

    ensure_file "${file}"

    LC_ALL=C grep -Fqx -- "${line}" "${file}" 2>/dev/null && return 0
    LC_ALL=C grep -Fqx -- "${line}"$'\r' "${file}" 2>/dev/null && return 0

    printf '%s\n' "${line}" >> "${file}" || die "Failed writing: ${file}" 2

}
ensure_path_once () {

    local rc="${1:-}"
    local alias_name="${2:-vx}"

    [[ -n "${rc}" ]] || die "ensure_path_once: missing rc" 2
    [[ -L "${rc}" ]] && die "Refusing to modify symlink: ${rc}" 2

    ensure_file "${rc}"

    ensure_line_once "${rc}" "# ${alias_name}"

    case "${rc}" in
        */.config/fish/config.fish)
            ensure_line_once "${rc}" 'set -gx PATH $HOME/.local/bin $PATH'
        ;;
        *)
            ensure_line_once "${rc}" 'export PATH="$HOME/.local/bin:$PATH"'
        ;;
    esac

}
install_launcher () {

    local root="${1:-}"
    local alias_name="${2:-vx}"

    [[ -n "${root}" ]] || die "install_launcher: missing root" 2
    is_valid_alias "${alias_name}" || die "Invalid alias: ${alias_name}" 2

    local run_sh="${root}/scripts/run.sh"
    [[ -f "${run_sh}" ]] || die "Missing: ${run_sh}" 2

    chmod +x "${run_sh}" >/dev/null 2>&1 || true

    local home=""
    home="$(home_dir)"

    local bin_dir="${home}/.local/bin"
    ensure_dir "${bin_dir}"

    local bin="${bin_dir}/${alias_name}"

    if [[ -e "${bin}" && ! -f "${bin}" ]]; then
        die "Refusing: target exists but not a file: ${bin}" 2
    fi
    [[ -L "${bin}" ]] && die "Refusing to overwrite symlink: ${bin}" 2

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
        'exec /usr/bin/env bash "${ROOT}/scripts/run.sh" "$@"' \
        > "${bin}" || die "Failed writing: ${bin}" 2

    chmod +x "${bin}" || die "chmod failed: ${bin}" 2
    printf '%s\n' "${bin}"

}
replace_file_literal () {

    local file="${1:-}"
    local old="${2:-}"
    local new="${3-}"

    [[ -n "${file}" ]] || return 2
    [[ -f "${file}" ]] || return 2
    [[ -n "${old}"  ]] || return 2
    [[ -L "${file}" ]] && return 2

    is_text_file "${file}" || return 2
    LC_ALL=C grep -Fq -- "${old}" "${file}" 2>/dev/null || return 1

    perl -i -pe '
        BEGIN {
            $old = $ARGV[0];
            $new = $ARGV[1];
            shift @ARGV; shift @ARGV;

            $new =~ s/\\/\\\\/g;
            $new =~ s/\$/\\\$/g;
            $new =~ s/\@/\\\@/g;
        }
        s/\Q$old\E/$new/g;
    ' "${old}" "${new}" "${file}" >/dev/null 2>&1 || return 2

    return 0

}
replace_tree_literal () {

    local root="${1:-}"
    local old="${2:-}"
    local new="${3-}"

    [[ -n "${root}" ]] || return 0
    [[ -n "${old}"  ]] || return 0
    [[ -e "${root}" ]] || return 0

    has find || return 0
    has grep || return 0
    has perl || return 0

    local -a ignore=(".git" "target" "node_modules" "dist" "build" ".next" ".venv" "venv" "__pycache__")
    local -a find_cmd=( find "${root}" )

    local -a dtests=()
    local x=""

    for x in "${ignore[@]}"; do
        dtests+=( -name "${x}" -o )
    done

    if (( ${#dtests[@]} > 0 )); then
        unset "dtests[${#dtests[@]}-1]"
        find_cmd+=( -type d \( "${dtests[@]}" \) -prune -o )
    fi

    find_cmd+=( -type f -print0 )

    local file="" rc=0
    local changed=0

    while IFS= read -r -d '' file; do

        replace_file_literal "${file}" "${old}" "${new}"
        rc=$?

        case "${rc}" in
            0) changed=1 ;;
            *) : ;;
        esac

    done < <("${find_cmd[@]}" 2>/dev/null)

    (( changed )) && return 0
    return 1

}
apply_placeholders () {

    local root="${1:-}"
    local alias_name="${2:-vx}"
    local user="${3-}"
    local name="${4-}"
    local repo="${5-}"

    [[ -n "${root}" ]] || return 0
    is_valid_alias "${alias_name}" || return 0

    has find && has grep && has perl || {
        if [[ -n "${user}${name}${repo}" ]]; then
            log "WARN: placeholders requested but perl/grep/find missing; skipping replacements."
        fi
        return 0
    }

    replace_tree_literal "${root}" "__alias__" "${alias_name}" >/dev/null 2>&1 || true

    [[ -n "${user}" ]] && replace_tree_literal "${root}" "__user__" "${user}" >/dev/null 2>&1 || true
    [[ -n "${name}" ]] && replace_tree_literal "${root}" "__name__" "${name}" >/dev/null 2>&1 || true
    [[ -n "${repo}" ]] && replace_tree_literal "${root}" "__repo__" "${repo}" >/dev/null 2>&1 || true

    return 0

}
install () {

    need_cmd grep
    need_cmd chmod
    need_cmd mkdir
    need_cmd dirname

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

    local here=""
    here="$(abs_dir "$(dirname -- "${BASH_SOURCE[0]}")")"

    local root=""
    root="$(abs_dir "${here}/..")"

    local bin_path=""
    bin_path="$(install_launcher "${root}" "${alias_name}")"

    local rc=""
    rc="$(detect_rc)"

    ensure_path_once "${rc}" "${alias_name}"

    apply_placeholders "${root}" "${alias_name}" "${gh_user}" "${proj_name}" "${gh_repo}"

    printf '%s\n' \
        "OK: installed ${bin_path}" \
        "OK: updated ${rc}" \
        "Reload: source \"${rc}\"" \
        "Then: ${alias_name} --help"

}

install "$@"
