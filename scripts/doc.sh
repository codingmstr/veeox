#!/usr/bin/env bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base.sh"

is_text_file () {

    local file="${1}"

    [[ -f "${file}" ]] || return 1
    [[ -s "${file}" ]] || return 0

    LC_ALL=C grep -Iq . -- "${file}" 2>/dev/null

}
replace () {

    ensure_pkg perl grep

    local file="${1:-}"
    local old="${2:-}"
    local new="${3-}"

    [[ -n "${file}" ]] || die "replace: missing file" 2
    [[ -f "${file}" ]] || die "replace: file not found: ${file}" 2
    [[ -n "${old}"  ]] || die "replace: missing old_word" 2

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
    ' "${old}" "${new}" "${file}" || die "replace: failed: ${file}" 2

    log "${file}: (${old}) -> (${new})"
    return 0

}
replace_all () {

    ensure_pkg find

    local ignore_arg=""
    local -a ignore_raw=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--ignore)
                ignore_arg="${2-}"
                [[ -n "${ignore_arg}" ]] || die "replace_all: missing value for --ignore" 2
                ignore_raw+=( "${ignore_arg}" )
                shift 2 || true
            ;;
            --)
                shift
                break
            ;;
            -*)
                die "replace_all: unknown option: $1" 2
            ;;
            *)
                break
            ;;
        esac
    done

    local old="${1:-}"
    local new="${2-}"
    local root="${3:-.}"

    [[ -n "${old}" ]] || die "replace_all: missing old_word" 2
    [[ -e "${root}" ]] || die "replace_all: path not found: ${root}" 2

    local total=0 changed=0 missed=0 skipped=0 failed=0
    local file="" rc=0

    if [[ -f "${root}" ]]; then

        total=1

        replace "${root}" "${old}" "${new}"
        rc=$?

        case "${rc}" in
            0) changed=1 ;;
            1) missed=1 ;;
            2) skipped=1 ;;
            *) failed=1 ;;
        esac

        log ""
        log "replace_all: total=${total} changed=${changed} missed=${missed} skipped=${skipped} failed=${failed}"

        (( failed == 0 )) || return 2
        (( changed > 0 )) && return 0 || return 1

    fi

    local root_clean="${root%/}"
    local -a ignore_list=(
        ".git" "target" "node_modules" "dist" "build" ".next"
        ".venv" "venv" "__pycache__"
    )

    local s="" part="" trimmed=""
    local -a parts=()

    for s in "${ignore_raw[@]-}"; do

        IFS=',' read -r -a parts <<< "${s}"

        for part in "${parts[@]-}"; do

            trimmed="${part#"${part%%[![:space:]]*}"}"
            trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
            [[ -n "${trimmed}" ]] || continue

            ignore_list+=( "${trimmed}" )

        done

    done

    local -a prune_name=() prune_root=() prune_path=()
    local -a excl_name=()  excl_root=()  excl_path=()
    local item="" p=""

    for item in "${ignore_list[@]-}"; do

        if [[ "${item}" == /* ]]; then

            p="${item#/}"
            [[ -n "${p}" ]] || continue

            prune_root+=( "${root_clean}/${p}" )
            excl_root+=( "${root_clean}/${p}" )

        elif [[ "${item}" == */* ]]; then

            prune_path+=( "*/${item}" )
            excl_path+=( "*/${item}" )

        else

            prune_name+=( "${item}" )
            excl_name+=( "${item}" )

        fi

    done

    local -a find_cmd=( find "${root_clean}" )
    local -a dtests=()
    local x=""

    for x in "${prune_name[@]-}"; do dtests+=( -name "${x}" -o ); done
    for x in "${prune_root[@]-}"; do dtests+=( -path "${x}" -o ); done
    for x in "${prune_path[@]-}"; do dtests+=( -path "${x}" -o ); done

    if (( ${#dtests[@]} > 0 )); then
        unset 'dtests[${#dtests[@]}-1]'
        find_cmd+=( -type d \( "${dtests[@]}" \) -prune -o )
    fi

    find_cmd+=( -type f )

    for x in "${excl_name[@]-}"; do find_cmd+=( ! -name "${x}" ); done
    for x in "${excl_root[@]-}"; do find_cmd+=( ! -path "${x}" ); done
    for x in "${excl_path[@]-}"; do find_cmd+=( ! -path "${x}" ); done

    find_cmd+=( -print0 )

    while IFS= read -r -d '' file; do

        (( total++ ))

        replace "${file}" "${old}" "${new}"
        rc=$?

        case "${rc}" in
            0) (( changed++ )) ;;
            1) (( missed++ )) ;;
            2) (( skipped++ )) ;;
            *) (( failed++ )) ;;
        esac

    done < <("${find_cmd[@]}" 2>/dev/null)

    log ""
    log "replace_all: total=${total} changed=${changed} missed=${missed} skipped=${skipped} failed=${failed}"

    (( failed == 0 )) || return 2
    (( changed > 0 )) && return 0 || return 1

}
set_placeholders () {

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

cmd_replace () {

    replace "$@"

}
cmd_replace_all () {

    replace_all "$@"

}
cmd_set_placeholders () {

    set_placeholders "$@"

}
