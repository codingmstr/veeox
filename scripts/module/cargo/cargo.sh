#!/usr/bin/env bash

cmd_cargo_help () {

    info_ln "Cargo :\n"

    printf '%s\n' \
        '    list                List of installed cargo tools/crates' \
        '    installed           Installed List of cargo tools' \
        '    install             Install crate/s' \
        '    uninstall           Uninstall crate/s' \
        '    install-update      Install/Update cargo tool/s into latest version' \
        '    show                Show package/tool/crate info, version if installed' \
        '    has-deps            Check if workspace/package has a spacific dependency' \
        '' \
        '    add                 Add new crate/s into <--package *>' \
        '    remove              remove crate/s from <--package *>' \
        '    update              Update crate/s' \
        '    upgrade             Upgrade crate/s into latest version' \
        '    info                Information about <*crate-name*>' \
        '    search              Search in crates store <*crate-name*>' \
        '' \
        '    new                 Create a new crate and (optionally) add it to the workspace' \
        '    build               Build the whole workspace, or a single crate if specified' \
        '    run                 Run a binary (use -p/--package to pick a crate, or pass a bin name)' \
        '' \
        '    check               Run compile checks for all crates and targets (no binaries produced)' \
        '    test                Run the full test suite (workspace-wide or a single crate)' \
        '    hack                Run feature matrix checks using cargo-hack (each-feature or powerset)' \
        '    fuzz                Run fuzz targets to find crashes/panics (uses cargo-fuzz)' \
        '    semver              Run cargo semver checks using cargo-semver-checks' \
        '    bench               Run benchmarks (workspace-wide or a single crate)' \
        '    example             Run an example target by name, forwarding extra args after --' \
        '    clean               Remove build artifacts' \
        '' \
        '    msrv                Get the latest minimum support rust version in all crates, return (env.RUST_MSRV if exists)' \
        '    msrv-check          Validate that your Rust compiler satisfies the workspace checks msrv' \
        '    msrv-test           Validate that your Rust compiler satisfies the workspace tests msrv' \
        '    nightly-check       Validate that your Rust compiler satisfies the workspace checks nightly version' \
        '    nightly-test        Validate that your Rust compiler satisfies the workspace tests nightly version' \
        '' \
        '    fix-ws              Remove trailing whitespace in git-tracked files' \
        '    check-fmt           Verify formatting --nightly (no changes)' \
        '    fix-fmt             Auto-format code --nightly' \
        '    check-fmt-stable    Verify formatting checks (no changes)' \
        '    fix-fmt-stable      Auto-format code' \
        '' \
        '    clippy              Run lints on crates/ only (strict)' \
        '    clippy-strict       Run lints on the full workspace (very strict)' \
        '' \
        '    spell-check         Spellcheck docs and text files' \
        '    spell-add           Add item into spellcheck dic file' \
        '    spell-remove        Remove item from spellcheck dic file' \
        '    coverage            Generate coverage reports (lcov + codecov json)' \
        '' \
        '    check-audit         Security advisory checks (policy gate)' \
        '    fix-audit           Apply automatic dependency upgrades to address advisories' \
        '' \
        '    check-prettier      Validate formatting for Markdown/YAML/etc. (no changes)' \
        '    fix-prettier        Auto-format Markdown/YAML/etc.' \
        '' \
        '    check-taplo         Validate TOML formatting (no changes)' \
        '    fix-taplo           Auto-format TOML files' \
        '' \
        '    check-doc           Build docs strictly (workspace or single crate)' \
        '    test-doc            Run documentation tests (doctests)' \
        '    open-doc            Build docs then open them in your browser' \
        '' \
        '    meta                Show workspace metadata (members, names, packages, publishable set)' \
        '    publish             Publish crates in dependency order (workspace publish)' \
        '    yank                Yank a published version (or undo yank)' \
        ''

}

cmd_stable () {

    stable_version

}
cmd_nightly () {

    nightly_version

}
cmd_msrv () {

    msrv_version

}
cmd_list () {

    ensure cargo
    run cargo --list "$@"

}
cmd_installed () {

    run_cargo install --list "$@"

}
cmd_install () {

    source <(parse "$@" -- :name:list)
    run_cargo install "${name[@]}" "${kwargs[@]}"

}
cmd_uninstall () {

    source <(parse "$@" -- :name:list)
    run_cargo uninstall "${name[@]}" "${kwargs[@]}"

}
cmd_install_update () {

    source <(parse "$@" -- :name:list="-a")
    ensure cargo-update cargo-install-update
    run_cargo install-update "${name[@]}" "${kwargs[@]}"

}
cmd_add () {

    source <(parse "$@" -- :crate_name:list :package:str)
    run_cargo add "${crate_name[@]}" --package "${package}" "${kwargs[@]}"

}
cmd_remove () {

    source <(parse "$@" -- :crate_name:list :package:str)
    run_cargo rm "${crate_name[@]}" --package "${package}" "${kwargs[@]}"

}
cmd_update () {

    source <(parse "$@" -- crate_name:list)
    run_cargo update "${crate_name[@]}" "${kwargs[@]}"

}
cmd_upgrade () {

    source <(parse "$@" -- crate_name:list)

    local -a pkg_args=()
    local p=""

    for p in "${crate_name[@]}"; do
        [[ -n "${p}" ]] || continue
        pkg_args+=( "--package" "${p}" )
    done

    ensure cargo-edit
    run_cargo upgrade "${pkg_args[@]}" "${kwargs[@]}"

}
cmd_info () {

    source <(parse "$@" -- :crate_name:list)
    run_cargo info "${crate_name[@]}" "${kwargs[@]}"

}
cmd_search () {

    run_cargo search "$@"

}
cmd_show () {

    source <(parse "$@" -- :name:str)

    local resolved="$(resolve_cmd "${name}")" || true
    [[ -n "${resolved}" ]] || { error "${name}: Not found."; return 1; }

    local -a cmd=()
    read -r -a cmd <<< "${resolved}"

    "${cmd[@]}" --version >/dev/null 2>&1 && { "${cmd[@]}" --version; return 0; }
    "${cmd[@]}" -V        >/dev/null 2>&1 && { "${cmd[@]}" -V;        return 0; }
    "${cmd[@]}" version   >/dev/null 2>&1 && { "${cmd[@]}" version;   return 0; }

    success "${resolved}: Installed."
    warn "${resolved}: can not detect version."

    return 0

}
cmd_has_deps () {

    source <(parse "$@" -- :keyword package:list p:list)

    local -a args=()
    local pkg=""

    for pkg in "${package[@]}"; do args+=( --package "${pkg}" ); done
    for pkg in "${p[@]}"; do args+=( --package "${pkg}" ); done

    run_cargo tree "${args[@]}" "${kwargs[@]}" | grep -nF -- "${keyword}"

}
cmd_expand () {

    source <(parse "$@" -- :package:list)

    local -a args=()
    local pkg=""
    for pkg in "${package[@]}"; do args+=( --package "${pkg}" ); done

    run_cargo expand --nightly "${args[@]}" "${kwargs[@]}"

}

cmd_new () {

    ensure perl
    source <(parse "$@" -- :name:str dir:str="crates" kind:str="--lib" publish:bool=true workspace:bool=true )

    local path="${dir}/${name}"
    [[ -e "${path}" ]] && die "Crate already exists: ${path}" 2
    [[ "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "Invalid crate name: ${name}" 2

    mkdir -p -- "${dir}" 2>/dev/null || true
    run_cargo new --vcs none "${kind}" "${kwargs[@]}" "${path}"

    if (( publish == 0 )); then

        local crate_toml="${path}/Cargo.toml"
        [[ -f "${crate_toml}" ]] || die "Cargo.toml not found: ${crate_toml}" 2

        perl -i -ne '
            our $nl;
            $nl //= (/\r\n$/ ? "\r\n" : "\n");

            our $in_pkg;
            our $inserted;

            if (/^\[package\]\s*\r?$/) {
                $in_pkg = 1;
                $inserted = 0;
                print;
                next;
            }
            if ($in_pkg) {

                if (/^\[[^\]]+\]\s*\r?$/) {
                    if (!$inserted) { print "publish = false$nl"; $inserted = 1; }
                    $in_pkg = 0;
                    print;
                    next;
                }
                if (/^[ \t]*publish\s*=/) {
                    next;
                }
                if (!$inserted && /^[ \t]*name\s*=/) {
                    print;
                    print "publish = false$nl";
                    $inserted = 1;
                    next;
                }

                print;
                next;
            }

            print;

            END {
                if ($in_pkg && !$inserted) {
                    print "publish = false$nl";
                }
            }
        ' "${crate_toml}" || die "Failed to set publish=false in ${crate_toml}" 2

    fi

    [[ ${workspace} -eq 1 ]] || return 0
    [[ -f Cargo.toml ]] || return 0

    grep -qF "\"${dir}/${name}\"" Cargo.toml 2>/dev/null && return 0

    MEMBER="${dir}/${name}" perl -0777 -i -pe '
        my $m = $ENV{MEMBER};
        my $ws = qr/\[workspace\]/s;

        if ($_ !~ $ws) { next; }

        if ($_ =~ /members\s*=\s*\[(.*?)\]/s) {
            my $block = $1;
            if ($block !~ /\Q$m\E/s) {
                s/(members\s*=\s*\[)(.*?)(\])/$1.$2."\n    \"$m\",\n".$3/se;
            }
        }
        else {
            s/(\[workspace\]\s*)/$1."members = [\n    \"$m\",\n]\n"/se;
        }
    ' Cargo.toml

}
cmd_build () {

    run_workspace build "$@"

}
cmd_run () {

    run_cargo run "$@"

}
cmd_clean () {

    run_cargo clean "$@"

}
cmd_clean_cache () {

    run_cargo ci-cache-clean "$@"

}
cmd_check () {

    run_workspace check features-on targets-on "$@"

}
cmd_test () {

    if has cargo-nextest; then

        run_workspace nextest run "$@"
        return 0

    fi

    run_workspace test "$@"

}
cmd_bench () {

    run_workspace bench features-on "$@"

}
cmd_example () {

    source <(parse "$@" -- :name package p)
    run_cargo run -p "${package:-${p:-examples}}" --example "${name}" "${kwargs[@]}"

}
cmd_check_doc () {

    run_workspace doc features-on deps-off "$@"

}
cmd_test_doc () {

    run_workspace test features-on --doc "$@"

}
cmd_clean_doc () {

    remove_dir "${ROOT_DIR}/target/doc"

}
cmd_open_doc () {

    run_workspace doc features-on deps-off "$@"

    local index=""

    if [[ -f "${ROOT_DIR}/target/doc/index.html" ]]; then
        index="${ROOT_DIR}/target/doc/index.html"
    else
        index="$(find "${ROOT_DIR}/target/doc" -maxdepth 2 -name index.html -print | head -n 1 || true)"
    fi

    open_path "${index}"

}

cmd_check_fmt () {

    run_cargo fmt --nightly --all -- --check "$@"

}
cmd_fix_fmt () {

    run_cargo fmt --nightly --all "$@"

}
cmd_check_fmt_stable () {

    run_cargo fmt --all -- --check "$@"

}
cmd_fix_fmt_stable () {

    run_cargo fmt --all "$@"

}
cmd_check_taplo () {

    ensure taplo
    run taplo fmt --check "$@"

}
cmd_fix_taplo () {

    ensure taplo
    run taplo fmt "$@"

}
cmd_check_audit () {

    run_cargo deny check advisories bans licenses sources "$@"

}
cmd_fix_audit () {

    local adv="${HOME}/.cargo/advisory-db"
    [[ -d "${adv}" ]] && [[ ! -d "${adv}/.git" ]] && mv "${adv}" "${adv}.broken.$(date +%s)" || true

    run_cargo audit fix "$@"

}
cmd_fix_ws () {

    ensure git perl

    local f=""

    while IFS= read -r -d '' f; do

        perl -0777 -ne 'exit 1 if /\0/; exit 0' -- "${f}" 2>/dev/null || continue
        perl -0777 -i -pe 's/[ \t]+$//mg if /[ \t]+$/m' -- "${f}"

    done < <(git ls-files -z)

}
cmd_check_prettier () {

    ensure node

    run npx -y prettier@3.3.3 --no-error-on-unmatched-pattern --check \
        ".github/**/*.{yml,yaml}" \
        "**/*.md" \
        ".prettierrc.yml" \
        "$@"

}
cmd_fix_prettier () {

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

cmd_clippy () {

    run_workspace_publishable clippy features-on targets-on "$@"

}
cmd_clippy_strict () {

    run_workspace clippy features-on targets-on "$@"

}
cmd_hack () {

    source <(parse "$@" -- depth:int=2 each_feature:bool)

    if (( each_feature )); then
        run_cargo hack check --keep-going --each-feature "${kwargs[@]}"
        return 0
    fi

    run_cargo hack check --keep-going --feature-powerset --depth "${depth}" "${kwargs[@]}"

}
cmd_udeps () {

    run_cargo udeps --nightly --all-targets "$@"

}
cmd_bloat () {

    source <(parse "$@" -- bin out)

    local -a args=()
    [[ -n "${bin}" ]] && args+=( --bin "${bin}" )

    if [[ -n "${out}" ]]; then

        [[ "${out}" == "1" ]] && out="bloat.info"
        [[ -n "${out}" ]] || die "bloat: invalid --out" 2
        [[ -d "${out}" ]] && die "bloat: --out is a directory: ${out}" 2

        run_cargo bloat "${args[@]}" "${kwargs[@]}" > "${out}"
        success "Analysed: out file -> ${out}"

        return $?
    fi

    run_cargo bloat "${args[@]}" "${kwargs[@]}"

}
cmd_fuzz () {

    local timeout="10" len="4096" have_max_total_time=0 have_max_len=0 in_post=0
    local -a pre=()
    local -a post=()

    while [[ $# -gt 0 ]]; do

        if [[ "$1" == "--" ]]; then
            in_post=1
            shift || true
            continue
        fi
        if (( in_post )); then
            case "$1" in
                -max_total_time|-max_total_time=*) have_max_total_time=1 ;;
                -max_len|-max_len=*) have_max_len=1 ;;
            esac
            post+=( "$1" )
            shift || true
            continue
        fi

        case "$1" in
            --timeout) shift || true; [[ $# -gt 0 ]] || die "Missing value for --timeout" 2; timeout="$1"; shift || true ;;
            --timeout=*) timeout="${1#*=}"; shift || true ;;
            --len) shift || true; [[ $# -gt 0 ]] || die "Missing value for --len" 2; len="$1"; shift || true ;;
            --len=*) len="${1#*=}"; shift || true ;;
            -max_total_time|-max_total_time=*) have_max_total_time=1; post+=( "$1" ); shift || true ;;
            -max_len|-max_len=*) have_max_len=1; post+=( "$1" ); shift || true ;;
            *) pre+=( "$1" ); shift || true ;;
        esac

    done

    if [[ "${#pre[@]}" -eq 0 ]] || [[ "${pre[0]-}" == -* ]]; then

        [[ "${timeout}" =~ ^[0-9]+$ ]] || die "Invalid --timeout: ${timeout}" 2
        [[ "${len}" =~ ^[0-9]+$ ]] || die "Invalid --len: ${len}" 2

        (( have_max_total_time )) || [[ "${timeout}" == "0" ]] || post+=( "-max_total_time=${timeout}" )
        (( have_max_len )) || [[ "${len}" == "0" ]] || post+=( "-max_len=${len}" )

        local -a targets=()
        while IFS= read -r line; do
            [[ -n "${line}" ]] || continue
            targets+=( "${line}" )
        done < <(run_cargo fuzz --nightly list 2>/dev/null || true)

        [[ "${#targets[@]}" -gt 0 ]] || die "No fuzz targets found. Run: cargo fuzz init && cargo fuzz add <name>" 2

        local t=""
        for t in "${targets[@]}"; do
            if [[ "${#post[@]}" -gt 0 ]]; then
                run_cargo fuzz --nightly run "${t}" "${pre[@]}" -- "${post[@]}" || die "Fuzzing failed: ${t}" 2
            else
                run_cargo fuzz --nightly run "${t}" "${pre[@]}" || die "Fuzzing failed: ${t}" 2
            fi
        done

        return 0
    fi
    if [[ "${#pre[@]}" -gt 0 ]]; then
        case "${pre[0]}" in
            run|list|init|add|clean|cmin|tmin|coverage|fmt) ;;
            *) pre=( "run" "${pre[@]}" ) ;;
        esac
    fi
    if [[ "${pre[0]}" == "run" ]]; then

        [[ "${timeout}" =~ ^[0-9]+$ ]] || die "Invalid --timeout: ${timeout}" 2
        [[ "${len}" =~ ^[0-9]+$ ]] || die "Invalid --len: ${len}" 2

        (( have_max_total_time )) || [[ "${timeout}" == "0" ]] || post+=( "-max_total_time=${timeout}" )
        (( have_max_len )) || [[ "${len}" == "0" ]] || post+=( "-max_len=${len}" )

    fi
    if [[ "${#post[@]}" -gt 0 ]]; then
        run_cargo fuzz --nightly "${pre[@]}" -- "${post[@]}"
        return $?
    fi

    run_cargo fuzz --nightly "${pre[@]}"

}
cmd_sanitizer () {

    source <(parse "$@" -- :sanitizer=asan command=test :target=auto clean:bool=0 track_origins:bool=1)

    local target="${target}" san="${sanitizer}" zsan="" opt="" tc="$(nightly_version)"
    local -a extra=()

    case "${san}" in
        asan|address)      san="asan"  ; zsan="address" ;;
        tsan|thread)       san="tsan"  ; zsan="thread" ;;
        lsan|leak)         san="lsan"  ; zsan="leak" ;;
        msan|memory)
            san="msan"
            zsan="memory"
            (( track_origins )) && extra+=( "-Zsanitizer-memory-track-origins" )
        ;;
        *) die "sanitizer: unknown sanitizer '${sanitizer}' (use: asan|tsan|msan|lsan)" 2 ;;
    esac

    if [[ -z "${target}" || "${target}" == "auto" ]]; then

        local vv="$(rustc +"${tc}" -vV 2>/dev/null)" || die "sanitizer: failed to read rustc -vV for ${tc}" 2
        target="$(awk '/^host: / { print $2; exit }' <<< "${vv}")"
        [[ -n "${target}" ]] || die "sanitizer: failed to detect host target." 2

    fi

    local target_dir="target/sanitizers/${san}"
    local rf="${RUSTFLAGS:-}"
    local rdf="${RUSTDOCFLAGS:-}"

    [[ -n "${rf}" ]] && rf+=" "
    [[ -n "${rdf}" ]] && rdf+=" "

    rf+="-Zsanitizer=${zsan} -Cforce-frame-pointers=yes -Cdebuginfo=1"
    rdf+="-Zsanitizer=${zsan} -Cforce-frame-pointers=yes -Cdebuginfo=1"

    for opt in "${extra[@]}"; do
        rf+=" ${opt}"
        rdf+=" ${opt}"
    done

    (( clean )) && { CARGO_TARGET_DIR="${target_dir}" run_cargo clean --nightly --target "${target}" >/dev/null 2>&1 || true; }

    CARGO_TARGET_DIR="${target_dir}" \
        CARGO_INCREMENTAL=0 \
        RUSTFLAGS="${rf}" \
        RUSTDOCFLAGS="${rdf}" \
        run_cargo "${command}" --nightly -Zbuild-std=std --target "${target}" "${kwargs[@]}"

}
cmd_miri () {

    source <(parse "$@" -- command=test :target=auto clean:bool setup:bool=1)

    local target="${target}" tc="$(nightly_version)"

    if [[ -z "${target}" || "${target}" == "auto" ]]; then

        local vv="$(rustc +"${tc}" -vV 2>/dev/null)" || die "miri: failed to read rustc -vV for ${tc}" 2
        target="$(awk '/^host: / { print $2; exit }' <<< "${vv}")"
        [[ -n "${target}" ]] || die "miri: failed to detect host target." 2

    fi

    local target_dir="target/miri"

    (( clean )) && { CARGO_TARGET_DIR="${target_dir}" run_cargo clean --nightly --target "${target}" >/dev/null 2>&1 || true; }
    (( setup )) && { CARGO_TARGET_DIR="${target_dir}" run_cargo miri --nightly setup >/dev/null 2>&1 || true; }

    CARGO_TARGET_DIR="${target_dir}" \
        CARGO_INCREMENTAL=0 \
        run_cargo miri --nightly "${command}" --target "${target}" "${kwargs[@]}"

}
cmd_coverage () {

    ensure llvm-tools-preview jq
    source <(parse "$@" -- mode=lcov name flags version token upload:bool package:list)

    local -a pkgs=()
    local out=""

    if [[ ${#package[@]} -gt 0 ]]; then

        local -a ws_pkgs=()
        mapfile -t ws_pkgs < <(run_cargo metadata --no-deps --format-version 1 2>/dev/null | jq -r '.packages[].name')

        local -A ws_set=()
        local -A seen=()
        local x="" p=""

        for x in "${ws_pkgs[@]-}"; do ws_set["${x}"]=1; done

        for p in "${package[@]-}"; do
            [[ -n "${ws_set[${p}]-}" ]] || die "Unknown workspace package: ${p}" 2
            [[ -n "${seen[${p}]-}" ]] && continue
            seen["${p}"]=1
            pkgs+=( -p "${p}" )
        done

        [[ ${#pkgs[@]} -gt 0 ]] || die "No packages selected" 2

    else

        while IFS= read -r line; do pkgs+=( -p "${line}" ); done < <(publishable_pkgs)
        [[ ${#pkgs[@]} -gt 0 ]] || die "No publishable workspace crates found" 2

    fi

    if [[ "${mode}" == "codecov" || "${mode}" == "json" ]]; then

        out="${ROOT_DIR}/codecov.json"
        run_cargo llvm-cov "${pkgs[@]}" --all-targets --all-features --codecov --output-path "${out}" "${kwargs[@]}"

    else

        out="${ROOT_DIR}/lcov.info"
        run_cargo llvm-cov "${pkgs[@]}" --all-targets --all-features --lcov --output-path "${out}" "${kwargs[@]}"

    fi

    if (( upload )); then

        ensure curl chmod mv mkdir

        [[ -n "${flags}" ]] || flags="crates"
        [[ -n "${name}" ]] || name="coverage-${GITHUB_RUN_ID:-local}"

        [[ -n "${version}" ]] || version="latest"
        [[ -n "${version}" && "${version}" != "latest" && "${version}" != v* ]] && version="v${version}"

        [[ -n "${token}" ]] || token="${CODECOV_TOKEN}"
        [[ -n "${token}" ]] || { error "Codecov: CODECOV_TOKEN is missing."; return 0; }
        [[ -f "${out}" ]] || { error "Codecov: file not found: ${out}"; return 0; }

        local os="$(uname -s | tr '[:upper:]' '[:lower:]')"
        local arch="$(uname -m)"
        local dist="linux"

        if [[ "${os}" == "darwin" ]]; then dist="macos"; fi
        if [[ "${dist}" == "linux" && ( "${arch}" == "aarch64" || "${arch}" == "arm64" ) ]]; then dist="linux-arm64"; fi

        local cache_dir="${ROOT_DIR}/.codecov/cache"
        mkdir -p -- "${cache_dir}"

        local resolved="${version}"
        local bin="${cache_dir}/codecov-${dist}-${resolved}"

        if [[ "${version}" == "latest" ]]; then

            local latest_page="$(curl -fsSL "https://cli.codecov.io/${dist}/latest" 2>/dev/null || true)"
            local v="$(printf '%s\n' "${latest_page}" | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"

            [[ -n "${v}" ]] && resolved="${v}"
            bin="${cache_dir}/codecov-${dist}-${resolved}"

        fi
        if [[ ! -x "${bin}" ]]; then

            local tmp="${bin}.tmp.$$"
            rm -f -- "${tmp}" 2>/dev/null || true

            local url_a="https://cli.codecov.io/${dist}/${resolved}/codecov"
            local url_b="https://cli.codecov.io/${resolved}/${dist}/codecov"

            if ! run curl -fsSL -o "${tmp}" "${url_a}"; then
                run curl -fsSL -o "${tmp}" "${url_b}"
            fi

            run chmod +x "${tmp}"
            run mv -f -- "${tmp}" "${bin}"

            run "${bin}" --version >/dev/null 2>&1

        fi

        local -a args=( --verbose upload-process --disable-search --fail-on-error -t "${token}" -f "${out}" )

        [[ -n "${flags}" ]] && args+=( -F "${flags}" )
        [[ -n "${name}"  ]] && args+=( -n "${name}" )

        run "${bin}" "${args[@]}"
        success "Ok: Codecov file upload successfully."

    fi

    success "OK Codecov processed successfully -> ${out}"

}
cmd_semver () {

    source <(parse "$@" -- baseline remote=origin)

    if [[ -z "${baseline}" ]]; then

        if is_ci_pull; then

            local base="${GITHUB_BASE_REF:-}"
            [[ -n "${base}" ]] || die "semver: missing GITHUB_BASE_REF. Provide --baseline <rev>." 2

            run git fetch --no-tags "${remote}" "${base}:refs/remotes/${remote}/${base}" >/dev/null 2>&1 || die "semver: failed to fetch." 2
            baseline="${remote}/${base}"

        elif is_ci_push; then

            run git fetch --tags --force --prune "${remote}" >/dev/null 2>&1 || true

            local cur="${GITHUB_REF_NAME:-}"

            baseline="$(
                git tag --list 'v*' --sort=-v:refname |
                grep -E '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' |
                grep -F -x -v -- "${cur}" |
                head -n 1 || true
            )"

            if [[ -z "${baseline}" ]]; then
                log "semver: first stable release -> Skipping."
                return 0
            fi

        else

            local def="$(git symbolic-ref -q "refs/remotes/${remote}/HEAD" 2>/dev/null || true)"
            def="${def#refs/remotes/${remote}/}"
            [[ -n "${def}" ]] || def="main"

            run git fetch --no-tags "${remote}" "${def}:refs/remotes/${remote}/${def}" >/dev/null 2>&1 || true

            if git show-ref --verify --quiet "refs/remotes/${remote}/${def}"; then
                baseline="${remote}/${def}"
            else
                log "semver: no baseline branch found (${remote}/${def}) -> Skipping."
                return 0
            fi

        fi
    fi

    [[ -n "${baseline}" ]] || { log "semver: no baseline. Skipping."; return 0; }
    git rev-parse --verify "${baseline}^{commit}" >/dev/null 2>&1 || die "semver: baseline '${baseline}' is not a valid." 2

    local -a extra=()
    run_cargo semver-checks -h 2>/dev/null | grep -q -- '--baseline-rev' && extra+=(--baseline-rev "${baseline}")

    run_cargo semver-checks "${extra[@]}" "${kwargs[@]}"

}

cmd_version () {

    ensure jq

    local name="${1:-}"
    local meta="$(run_cargo metadata --no-deps --format-version 1)" || die "Error: failed to read cargo metadata." 2

    if [[ -z "${name}" ]]; then

        local ws_root="$(jq -r '.workspace_root' <<<"${meta}")"
        local root_manifest="${ws_root}/Cargo.toml"

        local v="$(jq -r --arg m "${root_manifest}" '
            .packages[] | select(.manifest_path == $m) | .version
        ' <<<"${meta}" 2>/dev/null || true)"

        if [[ -z "${v}" || "${v}" == "null" ]]; then

            local id="$(jq -r '.workspace_members[0]' <<<"${meta}")"

            v="$(jq -r --arg id "${id}" '
                .packages[] | select(.id == $id) | .version
            ' <<<"${meta}")"

        fi

        [[ -n "${v}" && "${v}" != "null" ]] || die "Error: workspace version not found." 2

        printf '%s\n' "${v}"
        return 0

    fi

    local v="$(jq -r --arg n "${name}" '
        .packages[] | select(.name == $n) | .version
    ' <<<"${meta}" 2>/dev/null | head -n 1)"

    [[ -n "${v}" && "${v}" != "null" ]] || die "Error: package ${name} not found." 2
    printf '%s\n' "${v}"

}
cmd_is_publishable () {

    ensure grep tr
    source <(parse "$@" -- :name)

    local needle="$(printf '%s' "${name}" | tr '[:upper:]' '[:lower:]')"

    if publishable_pkgs | tr '[:upper:]' '[:lower:]' | grep -Fxq -- "${needle}"; then
        printf '%s\n' "yes"
        return 0
    fi

    printf '%s\n' "no"
    return 1

}
cmd_is_published () {

    ensure grep curl
    source <(parse "$@" -- :name)

    [[ "$(cmd_is_publishable "${name}")" == "yes" ]] || die "Error: package ${name} is not publishable." 2

    local version="$(cmd_version "${name}")"
    local name_lc="${name,,}"
    local n="${#name_lc}"
    local path=""

    if (( n == 1 )); then path="1/${name_lc}"
    elif (( n == 2 )); then path="2/${name_lc}"
    elif (( n == 3 )); then path="3/${name_lc:0:1}/${name_lc}"
    else path="${name_lc:0:2}/${name_lc:2:2}/${name_lc}"; fi

    local tmp="$(mktemp "${TMPDIR:-/tmp}/rust.XXXXXX" 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/rust.$$")"
    trap 'rm -f -- "${tmp}" 2>/dev/null || true; trap - RETURN' RETURN

    local code="$(curl -sSL --connect-timeout 5 --max-time 20 -o "${tmp}" -w '%{http_code}' "https://index.crates.io/${path}" 2>/dev/null || true)"
    [[ "${code}" =~ ^[0-9]{3}$ ]] || die "Error: crates.io request failed (network?)" 2

    if [[ "${code}" == "404" ]]; then
        echo "no"
        return 0
    fi
    if [[ "${code}" != "200" ]]; then
        die "Error: crates.io index request failed for ${name} (HTTP ${code})." 2
    fi
    if grep -Fq "\"vers\":\"${version}\"" "${tmp}"; then
        echo "yes"
        return 0
    fi

    echo "no"

}
cmd_can_publish () {

    source <(parse "$@" -- name)

    if [[ -n "${name}" ]]; then
        [[ "$(cmd_is_published "${name}")" == "yes" ]] && { echo "no"; return 0; }
        echo "yes"
        return 0
    fi

    local p=""
    local -a pkgs=()

    while IFS= read -r line; do pkgs+=( "${line}" ); done < <(publishable_pkgs)
    [[ ${#pkgs[@]} -gt 0 ]] || { echo "no"; return 0; }

    for p in "${pkgs[@]}"; do
        [[ "$(cmd_is_published "${p}")" == "yes" ]] && { echo "no"; return 0; }
    done

    echo "yes"

}
cmd_publish () {

    source <(parse "$@" -- token allow_dirty:bool dry_run:bool package:list)

    local old_token="" old_token_set=0 xtrace=0 i=0 p=""
    local -a cargo_args=()

    token="${token:-${CARGO_REGISTRY_TOKEN-}}"

    [[ -n "${token}" ]] || die "Missing registry token. Use --token or set CARGO_REGISTRY_TOKEN." 2
    [[ "${token}" =~ [[:space:]] ]] && die "Invalid token: ${token}." 2

    (( dry_run )) && cargo_args+=( --dry-run )

    if is_ci && ! is_ci_push; then
        die "Refusing publish in CI." 2
    fi
    if (( ! allow_dirty )) && has git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then

        if [[ -n "$(git status --porcelain --untracked-files=normal 2>/dev/null)" ]]; then
            die "Refusing publish with a dirty git working tree. Commit/stash changes, or pass --allow-dirty." 2
        fi

    fi
    if (( ! dry_run )) && ! is_ci; then

        local msg="About to publish "

        if [[ ${#package[@]} -gt 0 ]]; then
            msg+="package(s): ${package[*]}"
        else
            msg+="workspace"
        fi

        confirm "${msg}. Continue?" || die "Aborted." 1

    fi
    if [[ -n "${CARGO_REGISTRY_TOKEN+x}" ]]; then
        old_token_set=1
        old_token="${CARGO_REGISTRY_TOKEN}"
    fi
    if [[ -n "${token}" ]]; then

        [[ $- == *x* ]] && { xtrace=1; set +x; }
        export CARGO_REGISTRY_TOKEN="${token}"

        trap '
            if (( old_token_set )); then
                export CARGO_REGISTRY_TOKEN="${old_token}"
            else
                unset CARGO_REGISTRY_TOKEN
            fi

            (( xtrace )) && set -x

            trap - RETURN
        ' RETURN

    fi
    if [[ ${#package[@]} -gt 0 ]]; then

        for p in "${package[@]}"; do [[ "$(cmd_can_publish "${p}")" == "yes" ]] || die "Package: ${p} already published" 2; done
        for p in "${package[@]}"; do run_cargo publish --package "${p}" "${cargo_args[@]}" "${kwargs[@]}"; done

        return 0

    fi

    [[ "$(cmd_can_publish)" == "yes" ]] || die "There is some packages already published" 2
    run_cargo publish --workspace "${cargo_args[@]}" "${kwargs[@]}"

}
cmd_yank () {

    source <(parse "$@" -- :package :version token undo:bool)

    local old_token="" old_token_set=0 xtrace=0

    version="${version#v}"
    token="${token:-${CARGO_REGISTRY_TOKEN-}}"

    [[ -n "${token}" ]] || die "Missing registry token. Use --token or set CARGO_REGISTRY_TOKEN." 2
    [[ "${token}" =~ [[:space:]] ]] && die "Invalid token: ${token}." 2

    if is_ci && ! is_ci_push; then
        die "Refusing yank in CI." 2
    fi
    if ! is_ci; then

        (( undo )) || confirm "About to yank ${package} v${version}. Continue?" || die "Aborted." 1
        (( undo )) && confirm "About to undo yank ${package} v${version}. Continue?" || die "Aborted." 1

    fi
    if [[ -n "${CARGO_REGISTRY_TOKEN+x}" ]]; then
        old_token_set=1
        old_token="${CARGO_REGISTRY_TOKEN}"
    fi
    if [[ -n "${token}" ]]; then

        [[ $- == *x* ]] && { xtrace=1; set +x; }
        export CARGO_REGISTRY_TOKEN="${token}"

        trap '
            if (( old_token_set )); then
                export CARGO_REGISTRY_TOKEN="${old_token}"
            else
                unset CARGO_REGISTRY_TOKEN
            fi

            (( xtrace )) && set -x

            trap - RETURN
        ' RETURN

    fi
    if (( undo )); then
        run_cargo yank -p "${package}" --version "${version}" --undo "${kwargs[@]}"
        return 0
    fi

    run_cargo yank -p "${package}" --version "${version}" "${kwargs[@]}"

}
cmd_meta () {

    ensure jq tee

    local full=0
    local mode="pretty"
    local package=""
    local out=""
    local jq_color=0
    local jq_compact=0
    local only_published=0
    local members_names=0
    local registries=()
    local registries_set=0

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --full)
                full=1
                shift || true
            ;;
            --no-deps)
                full=0
                shift || true
            ;;
            -p|--package)
                shift || true
                package="${1:-}"
                [[ -n "${package}" ]] || die "Error: -p/--package requires a value" 2
                shift || true
            ;;
            --members)
                mode="members"
                shift || true
            ;;
            --names)
                mode="members"
                members_names=1
                shift || true
            ;;
            --packages)
                mode="packages"
                shift || true
            ;;
            --only-publishable)
                only_published=1
                shift || true
            ;;
            --registries|--registry)
                shift || true
                local raw="${1:-}"
                [[ -n "${raw}" ]] || die "Error: --registries requires a value" 2
                shift || true

                registries_set=1

                local tmp="${raw// /}"
                local parts=()
                local old_ifs="${IFS}"

                IFS=',' read -r -a parts <<< "${tmp}"
                IFS="${old_ifs}"

                local p=""
                for p in "${parts[@]}"; do
                    [[ -n "${p}" ]] || continue
                    registries+=( "${p}" )
                done
            ;;
            --compact|-c)
                jq_compact=1
                shift || true
            ;;
            --color|-C)
                jq_color=1
                shift || true
            ;;
            --out)
                shift || true
                out="${1:-}"
                [[ -n "${out}" ]] || die "Error: --out requires a value" 2
                shift || true
            ;;
            --)
                shift || true
                break
            ;;
            *)
                break
            ;;
        esac
    done

    if [[ -n "${package}" && "${mode}" == "members" ]]; then
        die "Error: -p/--package cannot be used with --members/--names" 2
    fi
    if (( registries_set )); then
        only_published=1
    fi
    if (( only_published )) && (( registries_set == 0 )); then
        registries=( "crates-io" )
    fi

    local cargo_args=( --format-version=1 )
    local jq_args=()

    (( full )) || cargo_args+=( --no-deps )
    (( jq_compact )) && jq_args+=( -c )
    (( jq_color )) && jq_args+=( -C )

    local jq_prelude=""
    local publishable_filter=""
    local regs_json="[]"
    local filter="."
    local base_ws_local='
        . as $m
        | ($m.workspace_members) as $ws
        | $m.packages[]
        | select(.id as $id | $ws | index($id) != null)
        | select(.source == null)
    '

    if (( only_published )); then

        regs_json="$(printf '%s\n' "${registries[@]}" | jq -Rn '[inputs]')"
        jq_args+=( --argjson regs "${regs_json}" )

        jq_prelude='
            def publish_allows:
                if .publish == null then
                    true
                elif .publish == false then
                    false
                elif (.publish | type) != "array" then
                    false
                elif (.publish | length) == 0 then
                    false
                elif ($regs | index("*")) != null then
                    true
                else
                    (.publish | any(. as $r | $regs | index($r) != null))
                end;
        '

        publishable_filter='
            | select(publish_allows)
        '

    fi

    if [[ -n "${package}" ]]; then

        jq_args+=( --arg p "${package}" )

        if (( only_published )); then
            filter="${jq_prelude}${base_ws_local}${publishable_filter} | select(.name == \$p)"
        else
            filter=".packages[] | select(.name == \$p)"
        fi

    else

        local stream=""

        if (( only_published )); then
            stream="${jq_prelude}${base_ws_local}${publishable_filter}"
        else
            stream=".packages[]"
        fi

        case "${mode}" in

            members)
                jq_args+=( -r )
                if (( members_names )); then
                    filter="${stream} | .name"
                else
                    filter="${stream} | .id"
                fi
            ;;
            packages)
                filter="${stream} | {name, version, publish, manifest_path}"
            ;;
            *)
                filter="${stream}"
            ;;

        esac

    fi

    if [[ -n "${out}" ]]; then
        run_cargo metadata "${cargo_args[@]}" | tee "${out}" | jq "${jq_args[@]}" "${filter}"
        return 0
    fi

    run_cargo metadata "${cargo_args[@]}" | jq "${jq_args[@]}" "${filter}"

}


cmd_ensure_vet () {

    [[ -f "${ROOT_DIR}/Cargo.lock" ]] || run_cargo generate-lockfile
    [[ -d "${ROOT_DIR}/supply-chain" ]] || run_cargo vet init

}
cmd_vet_fmt () {

    cmd_ensure_vet
    run_cargo vet fmt "$@"

}
cmd_vet_check () {

    cmd_ensure_vet
    run_cargo vet check "$@"

}
cmd_vet_suggest () {

    cmd_ensure_vet
    run_cargo vet suggest "$@"

}
cmd_vet_diff () {

    cmd_ensure_vet
    run_cargo vet diff "$@"

}
cmd_vet_import () {

    cmd_ensure_vet
    run_cargo vet import "$@"

}
cmd_vet_allow () {

    cmd_ensure_vet
    run_cargo vet trust "$@"

}
cmd_vet_deny () {

    cmd_ensure_vet
    run_cargo vet record-violation "$@"

}
cmd_vet_renew () {

    cmd_ensure_vet
    run_cargo vet renew "$@"

}
