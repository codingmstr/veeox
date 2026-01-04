#!/usr/bin/env bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base.sh"

is_text_file () {

    local file="${1}"

    [[ -f "${file}" ]] || return 1
    grep -Iq . "${file}" 2>/dev/null

}
print_replacements () {

    local file="${1}"

    local x=()

    grep -qF '__user__' "${file}" 2>/dev/null && x+=( "__user__=${INIT_NEW_USER}" )
    grep -qF '__repo__' "${file}" 2>/dev/null && x+=( "__repo__=${INIT_NEW_REPO}" )
    grep -qF '__name__' "${file}" 2>/dev/null && x+=( "__name__=${INIT_NEW_NAME}" )

    (( ${#x[@]} )) && printf '%s\n' "${file} -> ${x[*]}"

}
apply_replacements () {

    local file="${1}"

    if ! is_text_file "${file}"; then
        return 2
    fi

    grep -qE '(__user__|__repo__|__name__)' "${file}" 2>/dev/null || return 1

    print_replacements "${file}"

    perl -i -pe '
        my $u = $ENV{INIT_NEW_USER}; $u =~ s/\\/\\\\/g; $u =~ s/\$/\\\$/g;
        my $r = $ENV{INIT_NEW_REPO}; $r =~ s/\\/\\\\/g; $r =~ s/\$/\\\$/g;
        my $n = $ENV{INIT_NEW_NAME}; $n =~ s/\\/\\\\/g; $n =~ s/\$/\\\$/g;

        s/\Q__user__\E/$u/g;
        s/\Q__repo__\E/$r/g;
        s/\Q__name__\E/$n/g;
    ' "${file}"

    return 0

}
cmd_go () {

    cd_root
    need_cmd perl
    need_cmd grep
    need_cmd find

    local user=""
    local repo=""
    local name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --user) shift || true; user="${1:-}"; [[ -n "${user}" ]] || die "Error: --user requires a value" 2; shift || true ;;
            --repo) shift || true; repo="${1:-}"; [[ -n "${repo}" ]] || die "Error: --repo requires a value" 2; shift || true ;;
            --name) shift || true; name="${1:-}"; [[ -n "${name}" ]] || die "Error: --name requires a value" 2; shift || true ;;
            -h|--help)
                log "Usage: vx init --user \"myorg\" --repo \"my-repo\" --name \"My Name\""
                log "Tokens: __user__  __repo__  __name__"
                return 0
            ;;
            --) shift || true; break ;;
            -* ) die "Unknown arg: $1" 2 ;;
            * ) die "Unknown arg: $1" 2 ;;
        esac
    done

    [[ -n "${user}" ]] || die "Missing: --user" 2
    [[ -n "${repo}" ]] || die "Missing: --repo" 2
    [[ -n "${name}" ]] || die "Missing: --name" 2

    export INIT_NEW_USER="${user}"
    export INIT_NEW_REPO="${repo}"
    export INIT_NEW_NAME="${name}"

    local -a files=()
    local f=""

    while IFS= read -r -d '' f; do
        files+=( "${f}" )
    done < <(
        find "${ROOT_DIR}" \
            \( -path "${ROOT_DIR}/.git" -o -path "${ROOT_DIR}/.git/*" \
               -o -path "${ROOT_DIR}/target" -o -path "${ROOT_DIR}/target/*" \
               -o -path "${ROOT_DIR}/node_modules" -o -path "${ROOT_DIR}/node_modules/*" \
               -o -path "${ROOT_DIR}/dist" -o -path "${ROOT_DIR}/dist/*" \
               -o -path "${ROOT_DIR}/build" -o -path "${ROOT_DIR}/build/*" \
               -o -path "${ROOT_DIR}/.next" -o -path "${ROOT_DIR}/.next/*" \
               -o -path "${ROOT_DIR}/.vscode" -o -path "${ROOT_DIR}/.vscode/*" \
            \) -prune -o \
            -type f \
            -print0
    )

    (( ${#files[@]} > 0 )) || die "No files found" 2

    local changed=0
    local skipped=0

    for f in "${files[@]}"; do

        apply_replacements "${f}" && { changed=$(( changed + 1 )); continue; }

        case "$?" in
            1) : ;;
            2) skipped=$(( skipped + 1 )) ;;
            *) die "Failed editing: ${f}" 2 ;;
        esac

    done

    printf '%s\n' "Done. Updated files: ${changed}. Skipped non-text: ${skipped}."

}
