#!/usr/bin/env bash

cmd_lint_help () {

    info_ln "Lint :\n"

    printf '    %s\n' \
        "ws-fix              Remove trailing whitespace in git-tracked files" \
        "fmt-check           Verify formatting --nightly (no changes)" \
        "fmt-fix             Auto-format code --nightly" \
        "fmt-stable-check    Verify formatting checks (no changes)" \
        "fmt-stable-fix      Auto-format code" \
        "" \
        "taplo-check         Validate TOML formatting (no changes)" \
        "taplo-fix           Auto-format TOML files" \
        "" \
        "prettier-check      Validate formatting for Markdown/YAML/etc. (no changes)" \
        "prettier-fix        Auto-format Markdown/YAML/etc." \
        "" \
        "spell-check         Spellcheck docs and text files" \
        "spell-add           Add item into spellcheck dic file" \
        "spell-remove        Remove item from spellcheck dic file" \
        ''

}

cmd_ws_fix () {

    ensure git perl

    local f=""

    while IFS= read -r -d '' f; do

        perl -0777 -ne 'exit 1 if /\0/; exit 0' -- "${f}" 2>/dev/null || continue
        perl -0777 -i -pe 's/[ \t]+$//mg if /[ \t]+$/m' -- "${f}"

    done < <(git ls-files -z)

}
cmd_fmt_check () {

    run_cargo fmt --nightly --all -- --check "$@"

}
cmd_fmt_fix () {

    run_cargo fmt --nightly --all "$@"

}
cmd_fmt_stable_check () {

    run_cargo fmt --all -- --check "$@"

}
cmd_fmt_stable_fix () {

    run_cargo fmt --all "$@"

}

cmd_taplo_check () {

    ensure taplo
    run taplo fmt --check "$@"

}
cmd_taplo_fix () {

    ensure taplo
    run taplo fmt "$@"

}

cmd_prettier_check () {

    ensure node

    run npx -y prettier@3.3.3 --no-error-on-unmatched-pattern --check \
        ".github/**/*.{yml,yaml}" \
        "**/*.md" \
        ".prettierrc.yml" \
        "$@"

}
cmd_prettier_fix () {

    ensure node

    run npx -y prettier@3.3.3 --no-error-on-unmatched-pattern --write \
        ".github/**/*.{yml,yaml}" \
        "**/*.md" \
        ".prettierrc.yml" \
        "$@"

}

cmd_spell_check () {

    ensure head sed wc sort xargs
    source <(parse "$@" -- file=spellcheck.dic)

    file="${ROOT_DIR}/${file}"
    [[ -f "${file}" ]] || die "spellcheck: invalid dic file ${file}" 2

    local first_line="$(head -n 1 "${file}" || true)"
    [[ "${first_line}" =~ ^[0-9]+$ ]] || die "Error: The first line of ${file} must be an integer word count." 2

    local expected_count="${first_line}"
    local actual_count="$(sed '1d' "${file}" | wc -l | xargs)"

    local sort_locale="$(tool_pick_sort_locale)"
    local -a paths=( "${kwargs[@]}" )

    if [[ "${expected_count}" != "${actual_count}" ]]; then
        die "Error: Word count mismatch. Expected ${expected_count}, got ${actual_count}." 2
    fi
    if ! ( sed '1d' "${file}" | LC_ALL="${sort_locale}" sort -uc ) >/dev/null; then
        log "Dictionary is not sorted or has duplicates. Correct order is:"
        LC_ALL="${sort_locale}" sort -u <(sed '1d' "${file}")
        return 1
    fi
    if [[ ${#paths[@]} -eq 0 ]]; then
        shopt -s nullglob
        paths=( * )
        shopt -u nullglob
    fi

    run_cargo spellcheck --code 1 "${paths[@]}"
    success "All matching files use a correct spell-checking format."

}
cmd_spell_update () {

    source <(parse "$@" -- file action=add)

    local -a items=( "${kwargs[@]}" )
    (( ${#items[@]} )) || return 0

    [[ -n "${file}" ]] || file="spellcheck.dic"
    file="${ROOT_DIR}/${file}"
    ensure_file "${file}"

    local tmp_words="$(mktemp "${file}.words.XXXXXX" 2>/dev/null || printf '%s' "${file}.words.$$")"
    local tmp_out="$(mktemp "${file}.out.XXXXXX" 2>/dev/null || printf '%s' "${file}.out.$$")"

    awk '
        NR>=2 {
            sub(/\r$/, "")
            sub(/^[ \t]+/, "")
            sub(/[ \t]+$/, "")
            if ($0 != "") print
        }
    ' "${file}" 2>/dev/null > "${tmp_words}"

    case "${action}" in
        add)
            printf '%s\n' "${items[@]}" | awk '
                {
                    sub(/\r$/, "")
                    sub(/^[ \t]+/, "")
                    sub(/[ \t]+$/, "")
                    if ($0 != "") print
                }
            ' >> "${tmp_words}"

            LC_ALL=C sort -u -o "${tmp_words}" "${tmp_words}"
        ;;
        remove)
            local tmp_rm="$(mktemp "${file}.rm.XXXXXX" 2>/dev/null || printf '%s' "${file}.rm.$$")"
            local tmp_filt="$(mktemp "${file}.filt.XXXXXX" 2>/dev/null || printf '%s' "${file}.filt.$$")"

            printf '%s\n' "${items[@]}" | awk '
                {
                    sub(/\r$/, "")
                    sub(/^[ \t]+/, "")
                    sub(/[ \t]+$/, "")
                    if ($0 != "") print
                }
            ' | LC_ALL=C sort -u > "${tmp_rm}"

            awk '
                NR==FNR { rm[$0]=1; next }
                !($0 in rm) && $0 != "" { print }
            ' "${tmp_rm}" "${tmp_words}" > "${tmp_filt}"

            mv -f -- "${tmp_filt}" "${tmp_words}"
            LC_ALL=C sort -u -o "${tmp_words}" "${tmp_words}"

            rm -f -- "${tmp_rm}" 2>/dev/null || true
        ;;
        *)
            rm -f -- "${tmp_words}" "${tmp_out}" 2>/dev/null || true
            die "cmd_spell_update: invalid action '${action}'" 2
        ;;
    esac

    local count="$(wc -l < "${tmp_words}" | tr -d '[:space:]')"
    [[ -n "${count}" ]] || count="0"

    {
        printf '%s\n' "${count}"
        cat -- "${tmp_words}"
    } > "${tmp_out}" || {
        rm -f -- "${tmp_words}" "${tmp_out}" 2>/dev/null || true
        die "cmd_spell_update: write failed" 2
    }

    mv -f -- "${tmp_out}" "${file}" || {
        rm -f -- "${tmp_words}" "${tmp_out}" 2>/dev/null || true
        die "cmd_spell_update: update failed" 2
    }

    rm -f -- "${tmp_words}" 2>/dev/null || true
    return 0

}
cmd_spell_add () {

    cmd_spell_update spellcheck.dic add "$@"

}
cmd_spell_remove () {

    cmd_spell_update spellcheck.dic remove "$@"

}
