#!/usr/bin/env bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base.sh"

ensure_crate () {

    local crate="$1"
    local bin="${2:-$crate}"

    shift 2 || true
    has_cmd "${bin}" || run cargo install --locked "${crate}" "$@"

}
taplo_run () {

    if has_cmd taplo; then
        run taplo fmt "$@"
        return 0
    fi

    need_node
    run npx -y @taplo/cli@0.7.0 fmt "$@"

}
pick_sort_locale () {

    if has_cmd locale; then

        if locale -a 2>/dev/null | grep -qx "C\.UTF-8"; then
            printf '%s\n' "C.UTF-8"
            return 0
        fi
        if locale -a 2>/dev/null | grep -qx "en_US\.UTF-8"; then
            printf '%s\n' "en_US.UTF-8"
            return 0
        fi

    fi

    printf '%s\n' "C"

}
only_publish_pkgs () {

    cd_root
    need_cmd cargo
    need_cmd jq
    need_cmd sort

    run cargo metadata --format-version=1 --no-deps \
        | jq -r '
            def publish_list:
                if .publish == null then
                    ["crates-io"]
                elif .publish == false then
                    []
                elif (.publish | type) == "array" then
                    .publish
                else
                    []
                end;

            . as $m
            | ($m.workspace_members) as $ws
            | $m.packages[]
            | select(.id as $id | $ws | index($id) != null)
            | select(.source == null)
            | select((publish_list | length) > 0)
            | select(publish_list | index("crates-io") != null)
            | .name
        ' \
        | LC_ALL=C sort -u

}
clippy_flags () {

    printf '%s\n' \
        "-Dwarnings" \
        "-Dclippy::all" \
        "-Dclippy::correctness" \
        "-Dclippy::suspicious" \
        "-Dclippy::perf" \
        "-Dclippy::style" \
        "-Dclippy::complexity" \
        "-Wclippy::pedantic" \
        "-Wclippy::nursery" \
        "-Wclippy::cargo" \
        "-Dclippy::disallowed_methods" \
        "-Dclippy::disallowed_names" \
        "-Dclippy::disallowed_types" \
        "-Dclippy::disallowed_macros"

}
cargo_test_like () {

    local sub="${1}"
    shift || true

    cd_root
    need_cmd cargo

    if [[ $# -eq 0 ]]; then
        run cargo "${sub}" --workspace --all-features
        return 0
    fi
    if [[ "${1:-}" == "-p" || "${1:-}" == "--package" ]]; then

        shift || true

        local package="${1:-}"
        [[ -n "${package}" ]] || die "Error: -p/--package requires a value" 2

        shift || true

        run cargo "${sub}" -p "${package}" --all-features "$@"
        return 0

    fi

    run cargo "${sub}" --workspace --all-features "$@"

}
cargo_help () {

    cat <<'OUT'
    ensure           Ensure all vx used crates installed
    new              Create a new crate and (optionally) add it to the workspace
    build            Build the whole workspace, or a single crate if specified
    run              Run a binary (use -p/--package to pick a crate, or pass a bin name)

    check            Fast compile checks for all crates and targets (no binaries produced)
    test             Run the full test suite (workspace-wide or a single crate)
    bench            Run benchmarks (workspace-wide or a single crate)
    example          Run an example target by name, forwarding extra args after --
    clean            Remove build artifacts

    msrv             Validate that your Rust compiler satisfies the workspace MSRV
    doctor           Show tool versions and optional tooling availability

    fix-ws           Remove trailing whitespace in git-tracked files
    check-fmt        Verify formatting (no changes)
    fix-fmt          Auto-format code

    clippy           Run lints on crates/ only (strict)
    clippy-strict    Run lints on the full workspace (very strict)

    deny             Supply-chain / policy checks (advisories, licenses, bans, sources)
    spellcheck       Spellcheck docs and text files
    coverage         Generate coverage reports (lcov + codecov json)

    check-audit      Security advisory checks (policy gate)
    fix-audit        Apply automatic dependency upgrades to address advisories

    check-prettier   Validate formatting for Markdown/YAML/etc. (no changes)
    fix-prettier     Auto-format Markdown/YAML/etc.

    check-taplo      Validate TOML formatting (no changes)
    fix-taplo        Auto-format TOML files

    check-doc        Build docs strictly (workspace or single crate)
    test-doc         Run documentation tests (doctests)
    open-doc         Build docs then open them in your browser

    ci               Run a local CI-like workflow (checks + tests + lints)
    meta             Show workspace metadata (members, names, packages, publishable set)
    publish          Publish crates in dependency order (workspace publish)
OUT
}

cmd_ensure () {

    cd_root
    need_cmd cargo
    need_cmd grep

    log "== Installing Dependencies =="

    ensure_crate "cargo-deny" "cargo-deny"
    ensure_crate "cargo-audit" "cargo-audit" --features fix
    ensure_crate "cargo-spellcheck" "cargo-spellcheck"
    ensure_crate "cargo-llvm-cov" "cargo-llvm-cov"
    ensure_crate "taplo-cli" "taplo"

    if has_cmd rustup; then
        if ! rustup component list --installed 2>/dev/null | grep -qE '^(llvm-tools|llvm-tools-preview)\b'; then
            run rustup component add llvm-tools-preview
        fi
    fi

    log "== Done =="

}
cmd_new () {

    cd_root
    need_cmd cargo
    need_cmd perl

    local kind="--lib"
    local dir="crates"
    local add_workspace=1
    local name=""
    local -a pass=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lib|--bin)
                kind="$1"
                shift || true
            ;;
            --dir)
                shift || true
                [[ -n "${1:-}" ]] || die "Error: --dir requires a value" 2
                dir="$1"
                shift || true
            ;;
            --no-workspace)
                add_workspace=0
                shift || true
            ;;
            --)
                shift
                pass+=( "$@" )
                break
            ;;
            -*)
                pass+=( "$1" )
                shift || true
            ;;
            *)
                name="$1"
                shift || true
                pass+=( "$@" )
                break
            ;;
        esac
    done

    [[ -n "${name}" ]] || die "Usage: cmd_new [--lib|--bin] [--dir <dir>] [--no-workspace] <name> [-- <cargo new args>]" 2

    local path="${dir}/${name}"
    [[ -e "${path}" ]] && die "Error: already exists: ${path}" 2

    run cargo new --vcs none "${kind}" "${path}" "${pass[@]}"

    [[ ${add_workspace} -eq 1 ]] || return 0
    [[ -f Cargo.toml ]] || return 0

    grep -qE '^\s*members\s*=\s*\[.*"'"${dir}"'/\*".*\]' Cargo.toml 2>/dev/null && return 0

    VX_MEMBER="${dir}/${name}" perl -0777 -i -pe '
        my $m = $ENV{VX_MEMBER};
        my $ws = qr/\[workspace\]/s;

        if ($_ !~ $ws) { exit 0; }

        if ($_ =~ /members\s*=\s*\[(.*?)\]/s) {
            my $block = $1;
            if ($block !~ /\Q$m\E/s) {
                s/(members\s*=\s*\[)(.*?)(\])/$1.$2."\n    \"$m\",\n".$3/se;
            }
        } else {
            s/(\[workspace\]\s*)/$1."members = [\n    \"$m\",\n]\n"/se;
        }
    ' Cargo.toml

}
cmd_build () {

    cd_root
    need_cmd cargo

    if [[ $# -gt 0 ]]; then
        run cargo build "$@"
        return $?
    fi

    run cargo build --workspace

}
cmd_run () {

    cd_root
    need_cmd cargo

    local pkg=""
    local bin=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--package)
                shift || true
                pkg="${1:-}"
                [[ -n "${pkg}" ]] || die "Error: -p/--package requires a value" 2
                shift || true
            ;;
            --bin)
                shift || true
                bin="${1:-}"
                [[ -n "${bin}" ]] || die "Error: --bin requires a value" 2
                shift || true
            ;;
            --)
                shift || true
                break
            ;;
            *)
                if [[ -z "${bin}" && "${1:0:1}" != "-" ]]; then
                    bin="$1"
                    shift || true
                else
                    break
                fi
            ;;
        esac
    done

    if [[ -n "${bin}" ]]; then
        if [[ -n "${pkg}" ]]; then
            run cargo run -p "${pkg}" --bin "${bin}" -- "$@"
        else
            run cargo run --bin "${bin}" -- "$@"
        fi
        return $?
    fi
    if [[ -n "${pkg}" ]]; then
        run cargo run -p "${pkg}" -- "$@"
        return $?
    fi

    run cargo run "$@"

}
cmd_check () {

    cd_root
    need_cmd cargo
    run cargo check --workspace --all-targets --all-features "$@"

}
cmd_fix_ws () {

    cd_root
    need_cmd git
    need_cmd perl

    local f=""

    while IFS= read -r -d '' f; do
        perl -pi -e 's/[ \t]+$//' "${f}"
    done < <(git ls-files -z)

}
cmd_check_fmt () {

    cd_root
    need_cmd cargo
    run cargo fmt --all --check "$@"

}
cmd_fix_fmt () {

    cd_root
    need_cmd cargo
    run cargo fmt --all "$@"

}
cmd_check_doc () {

    cd_root
    need_cmd cargo

    if [[ $# -eq 0 ]]; then
        RUSTDOCFLAGS="-Dwarnings" run cargo doc --workspace --all-features --no-deps
        return 0
    fi
    if [[ "${1:-}" == "-p" || "${1:-}" == "--package" ]]; then

        shift || true

        local package="${1:-}"
        [[ -n "${package}" ]] || die "Error: -p/--package requires a value" 2

        shift || true

        RUSTDOCFLAGS="-Dwarnings" run cargo doc -p "${package}" --all-features --no-deps "$@"
        return 0

    fi

    RUSTDOCFLAGS="-Dwarnings" run cargo doc --workspace --all-features --no-deps "$@"

}
cmd_test_doc () {

    cd_root
    need_cmd cargo

    if [[ $# -eq 0 ]]; then
        RUSTDOCFLAGS="-Dwarnings" run cargo test --workspace --all-features --doc
        return 0
    fi
    if [[ "${1:-}" == "-p" || "${1:-}" == "--package" ]]; then

        shift || true

        local package="${1:-}"
        [[ -n "${package}" ]] || die "Error: -p/--package requires a value" 2

        shift || true

        RUSTDOCFLAGS="-Dwarnings" run cargo test -p "${package}" --all-features --doc "$@"
        return 0

    fi

    RUSTDOCFLAGS="-Dwarnings" run cargo test --workspace --all-features --doc "$@"

}
cmd_clean_doc () {

    cd_root
    need_cmd cargo
    run cargo clean --doc

}
cmd_open_doc () {

    cd_root
    need_cmd cargo

    run cargo doc --workspace --all-features --no-deps "$@"
    local index=""

    if [[ -f "${ROOT_DIR}/target/doc/index.html" ]]; then
        index="${ROOT_DIR}/target/doc/index.html"
    else
        index="$(find "${ROOT_DIR}/target/doc" -maxdepth 2 -name index.html -print | head -n 1 || true)"
    fi

    [[ -n "${index}" && -f "${index}" ]] || die "Docs index not found under target/doc" 2

    open_path "${index}"

}
cmd_clippy () {

    cd_root
    need_cmd cargo
    need_cmd jq

    local -a pkgs=()
  
    while IFS= read -r line; do
        pkgs+=( "${line}" )
    done < <(only_publish_pkgs)
  
    [[ ${#pkgs[@]} -gt 0 ]] || die "No publishable workspace crates found" 2

    local args=()
    for p in "${pkgs[@]}"; do args+=( -p "${p}" ); done

    mapfile -t flags < <(clippy_flags)
    run cargo clippy "${args[@]}" --all-targets --all-features "$@" -- "${flags[@]}"

}
cmd_clippy_strict () {

    cd_root
    need_cmd cargo
    mapfile -t flags < <(clippy_flags)
    run cargo clippy --workspace --all-targets --all-features "$@" -- "${flags[@]}"

}
cmd_deny () {

    cd_root
    need_cmd cargo

    if has_cmd cargo-deny; then
        run cargo deny check "$@"
        return 0
    fi

    log "cargo-deny is not installed."
    log "Install: cargo install cargo-deny"
    exit 2

}
cmd_test () {

    cargo_test_like test "$@"

}
cmd_bench () {

    cargo_test_like bench "$@"

}
cmd_example () {

    cd_root
    need_cmd cargo

    local name="${1:-}"

    [[ -n "${name}" ]] || {
        log "Usage: vx example <name> [-p <package>] [-- <args...>]"
        log "Examples:"
        log "  vx example web"
        log "  vx example web -p examples"
        log "  vx example web -p examples -- --args"
        exit 2
    }

    shift || true
    local package="examples"

    while [[ $# -gt 0 ]]; do

        case "${1}" in

            -p|--package)
                shift || true
                package="${1:-}"
                [[ -n "${package}" ]] || die "Error: -p/--package requires a value" 2
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

    run cargo run -p "${package}" --example "${name}" -- "$@"

}
cmd_clean () {

    cd_root
    need_cmd cargo
    run cargo clean

}
cmd_msrv () {

    cd_root
    need_cmd cargo
    need_cmd rustc
    need_cmd jq

    local want=""
    local have=""

    want="$(
        cargo metadata --no-deps --format-version 1 |
        jq -r '.packages[].rust_version // empty' |
        sort -V |
        tail -n 1
    )"

    have="$(rustc -V | awk '{print $2}')"

    [[ -n "${want}" ]] || { log "Workspace MSRV: ${have} (fallback: no rust-version) | rustc: ${have}"; return 0; }
    [[ "$(printf '%s\n%s\n' "${want}" "${have}" | sort -V | head -n 1)" == "${want}" ]] || die "Rust too old: need >= ${want}, have ${have}" 2

    log "Workspace MSRV: ${want} | rustc: ${have}"

}
cmd_doctor () {

    cd_root
    log "== Doctor =="

    has_cmd rustc || die "rustc not found"
    has_cmd cargo || die "cargo not found"

    rustc -V
    cargo -V

    if has_cmd cargo-deny; then
        run cargo deny --version || true
    else
        log "cargo-deny: not installed (optional) -> cargo install cargo-deny"
    fi

    if run cargo spellcheck --version >/dev/null 2>&1; then
        run cargo spellcheck --version || true
    else
        log "cargo-spellcheck: not installed (optional) -> cargo install --locked cargo-spellcheck"
    fi

    if run cargo llvm-cov --version >/dev/null 2>&1; then
        run cargo llvm-cov --version || true
    else
        log "cargo-llvm-cov: not installed (optional) -> cargo install --locked cargo-llvm-cov"
    fi

    log "=================="
    log "OK"

}
cmd_coverage () {

    cd_root
    need_cmd cargo
    need_cmd jq

    local mode="${1:-lcov}"

    if [[ "${mode}" == "lcov" || "${mode}" == "codecov" || "${mode}" == "json" ]]; then
        shift || true
    else
        mode="lcov"
    fi

    if ! run cargo llvm-cov --version >/dev/null 2>&1; then
        log "cargo-llvm-cov is not installed."
        log "Install:"
        log "  rustup component add llvm-tools"
        log "  cargo install --locked cargo-llvm-cov"
        exit 2
    fi
    if has_cmd rustup; then
        if ! run rustup component list --installed 2>/dev/null | grep -Eq '^(llvm-tools|llvm-tools-preview)\b'; then
            log "Missing Rust component: llvm-tools (or llvm-tools-preview)"
            log "Install one of:"
            log "  rustup component add llvm-tools"
            log "  rustup component add llvm-tools-preview"
            exit 2
        fi
    fi

    local -a pkgs=()

    while IFS= read -r line; do
        pkgs+=( "${line}" )
    done < <(only_publish_pkgs)

    [[ ${#pkgs[@]} -gt 0 ]] || { log "No publishable workspace crates found"; exit 1; }

    local args=()
    for p in "${pkgs[@]}"; do args+=( -p "${p}" ); done

    local out="${ROOT_DIR}/lcov.info"
    [[ "${mode}" == "codecov" || "${mode}" == "json" ]] && out="${ROOT_DIR}/codecov.json"

    if [[ "${mode}" == "codecov" || "${mode}" == "json" ]]; then
        run cargo llvm-cov "${args[@]}" --all-targets --all-features --codecov --output-path "${out}" "$@"
    else
        run cargo llvm-cov "${args[@]}" --all-targets --all-features --lcov --output-path "${out}" "$@"
    fi

    log
    log "OK -> ${out}"

}
cmd_spellcheck () {

    cd_root
    need_cmd cargo
    need_cmd head
    need_cmd sed
    need_cmd wc
    need_cmd sort
    need_cmd grep
    need_cmd xargs

    if ! run cargo spellcheck --version >/dev/null 2>&1; then
        log "cargo-spellcheck is not installed."
        log "Install: cargo install --locked cargo-spellcheck"
        exit 2
    fi

    local file="${ROOT_DIR}/spellcheck.dic"
    need_file "${file}"

    local first_line
    first_line="$(head -n 1 "${file}" || true)"

    if ! [[ "${first_line}" =~ ^[0-9]+$ ]]; then
        die "Error: The first line of ${file} must be an integer word count, got: '${first_line}'" 2
    fi

    local expected_count="${first_line}"
    local actual_count
    actual_count="$(sed '1d' "${file}" | wc -l | xargs)"

    local sort_locale
    sort_locale="$(pick_sort_locale)"

    if [[ "${expected_count}" != "${actual_count}" ]]; then
        die "Error: Word count mismatch. Expected ${expected_count}, got ${actual_count}." 2
    fi

    if ! ( sed '1d' "${file}" | LC_ALL="${sort_locale}" sort -uc ) >/dev/null; then
        log "Dictionary is not sorted or has duplicates. Correct order is:"
        LC_ALL="${sort_locale}" sort -u <(sed '1d' "${file}")
        exit 1
    fi

    local paths=("$@")

    if [[ ${#paths[@]} -eq 0 ]]; then
        shopt -s nullglob
        paths=( * )
        shopt -u nullglob
    fi

    run cargo spellcheck --code 1 "${paths[@]}"

    if grep -I --exclude-dir=.git --exclude-dir=target --exclude-dir=scripts -nRE '[[:blank:]]+$' .; then
        log
        die "Please remove trailing whitespace from these lines." 1
    fi

    log "All matching files use a correct spell-checking format."

}
cmd_check_prettier () {

    cd_root
    need_node

    npx -y prettier@3.3.3 --no-error-on-unmatched-pattern --check \
        ".github/**/*.{yml,yaml}" \
        "**/*.md" \
        ".prettierrc.yml" \
        "$@"

}
cmd_fix_prettier () {

    cd_root
    need_node

    npx -y prettier@3.3.3 --no-error-on-unmatched-pattern --write \
        ".github/**/*.{yml,yaml}" \
        "**/*.md" \
        ".prettierrc.yml" \
        "$@"

}
cmd_check_taplo () {

    cd_root
    taplo_run --check "$@"

}
cmd_fix_taplo () {

    cd_root
    taplo_run "$@"

}
cmd_check_audit () {

    cd_root
    need_cmd cargo
    has_cmd cargo-deny || die "Error: cargo-deny not found. Install: cargo install cargo-deny" 2
    run cargo deny check advisories bans licenses sources "$@"

}
cmd_fix_audit () {

    cd_root
    need_cmd cargo
    has_cmd cargo-audit || die "Error: cargo-audit not found. Install: cargo install cargo-audit --locked --features=fix" 2
    run cargo audit fix "$@"

}
cmd_ci () {

    cd_root
    need_cmd cargo

    printf "\n💥 Checking ...\n\n"
    "${SELF}" check

    printf "\n💥 Testing ...\n\n"
    "${SELF}" test

    printf "\n💥 Clippy ...\n\n"
    "${SELF}" clippy

    printf "\n💥 Check Audit ...\n\n"
    "${SELF}" check-audit

    printf "\n💥 Check Doc ...\n\n"
    "${SELF}" check-doc

    printf "\n💥 Check Format ...\n\n"
    "${SELF}" check-fmt

    printf "\n💥 Check Taplo ...\n\n"
    "${SELF}" check-taplo

    printf "\n💥 Check Prettier ...\n\n"
    "${SELF}" check-prettier

    printf "\n💥 Check Spellcheck ...\n\n"
    run cargo spellcheck --version >/dev/null 2>&1 && "${SELF}" spellcheck || log "skip: cargo-spellcheck not installed"

    printf "\n✅ CI pipeline succeeded.\n\n"

}
cmd_publish () {

    cd_root
    need_cmd cargo

    local dry_run=0
    local token=""
    local -a packages=()
    local -a excludes=()
    local -a cargo_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--package)
                shift || true
                [[ -n "${1:-}" ]] || die "Error: -p/--package requires a value" 2
                packages+=( "$1" )
                shift || true
            ;;
            --package=*)
                local v="${1#*=}"
                [[ -n "${v}" ]] || die "Error: --package requires a value" 2
                packages+=( "${v}" )
                shift || true
            ;;
            --exclude|--execlude)
                shift || true
                [[ -n "${1:-}" ]] || die "Error: --exclude requires a value" 2
                excludes+=( "$1" )
                shift || true
            ;;
            --exclude=*|--execlude=*)
                local v="${1#*=}"
                [[ -n "${v}" ]] || die "Error: --exclude requires a value" 2
                excludes+=( "${v}" )
                shift || true
            ;;
            --token)
                shift || true
                token="${1:-}"
                [[ -n "${token}" ]] || die "Error: --token requires a value" 2
                shift || true
            ;;
            --token=*)
                token="${1#*=}"
                [[ -n "${token}" ]] || die "Error: --token requires a value" 2
                shift || true
            ;;
            --dry-run|--dryrun|--dryr-run)
                dry_run=1
                shift || true
            ;;
            --)
                shift
                break
            ;;
            *)
                break
            ;;
        esac
    done

    [[ ${#packages[@]} -gt 0 && ${#excludes[@]} -gt 0 ]] && die "Error: --exclude cannot be used with --package/-p (exclude requires --workspace)" 2
    [[ ${dry_run} -eq 1 ]] && cargo_args+=( --dry-run )
    [[ -n "${token}" ]] && cargo_args+=( --token "${token}" )

    local i=0
    while [[ $i -lt ${#excludes[@]} ]]; do
        cargo_args+=( --exclude "${excludes[$i]}" )
        i=$(( i + 1 ))
    done

    i=0
    while [[ $i -lt ${#packages[@]} ]]; do
        cargo_args+=( --package "${packages[$i]}" )
        i=$(( i + 1 ))
    done

    [[ ${#packages[@]} -gt 0 ]] && { run cargo publish "${cargo_args[@]}" "$@"; return $?; }

    run cargo publish --workspace "${cargo_args[@]}" "$@"

}
cmd_meta () {

    cd_root
    need_cmd cargo
    need_cmd jq

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
            --only-publish)
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
        need_cmd tee
        run cargo metadata "${cargo_args[@]}" | tee "${out}" | jq "${jq_args[@]}" "${filter}"
        return 0
    fi

    run cargo metadata "${cargo_args[@]}" | jq "${jq_args[@]}" "${filter}"

}
