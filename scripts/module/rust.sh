#!/usr/bin/env bash

stable_version () {

    tool_stable_version

}
nightly_version () {

    tool_nightly_version


}
msrv_version () {

    tool_msrv_version

}
publishable_pkgs () {

    ensure cargo jq

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
    | tool_sort_uniq

}
run_cargo () {

    ensure cargo

    local sub="${1:-}" tc="" mode="stable"
    [[ -n "${sub}" ]] || die "run_cargo requires a cargo subcommand." 2
    shift || true

    case "${sub}" in
        add|bench|build|check|test|clean|doc|fetch|fix|generate-lockfile|help|init|install|locate-project|login|logout|metadata|new) : ;;
        owner|package|pkgid|publish|remove|report|run|rustc|rustdoc|search|tree|uninstall|update|vendor|verify-project|version|yank) : ;;
        fmt) ensure rustfmt ;;
        clippy) ensure "${sub}" ;;
        *) ensure "cargo-${sub}" ;;
    esac

    local use_plus=0 need_docflags=0
    local -a pass=()

    has rustup && use_plus=1

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--nightly) mode="nightly"; shift || true ;;
            -m|--msrv|--min) mode="msrv"; shift || true ;;
            -s|--stable) mode="stable"; shift || true ;;
            --)
                pass+=( "--" )
                shift || true
                pass+=( "$@" )
                break
            ;;
            *) pass+=( "$1" ); shift || true ;;
        esac
    done

    if (( use_plus )); then

        if [[ "${mode}" == "nightly" ]]; then
            tc="$(tool_nightly_version)"
        elif [[ "${mode}" == "msrv" ]]; then
            tc="$(tool_msrv_version)"
        else
            tc="$(tool_stable_version)"
        fi

    else

        [[ "${mode}" == "stable" ]] || die "rustup not found: Use --stable or install rustup." 2

    fi

    if [[ "${sub}" == "doc" || "${sub}" == "rustdoc" ]]; then

        need_docflags=1

    elif [[ "${sub}" == "test" ]]; then

        local a=""

        for a in "${pass[@]}"; do
            [[ "${a}" == "--doc" ]] && { need_docflags=1; break; }
        done

    fi

    if (( need_docflags )); then

        local docflags="$(tool_docflags_deny)"

        if (( use_plus )); then
            RUSTDOCFLAGS="${docflags}" run cargo +"${tc}" "${sub}" "${pass[@]}"
            return $?
        fi

        RUSTDOCFLAGS="${docflags}" run cargo "${sub}" "${pass[@]}"
        return $?

    fi
    if (( use_plus )); then

        run cargo +"${tc}" "${sub}" "${pass[@]}"
        return $?

    fi

    run cargo "${sub}" "${pass[@]}"

}
run_workspace () {

    local command="${1:-}" features=0 targets=0 no_deps=0 all=0 workspace=1 a="" nested=""
    local -a extra=()

    [[ -n "${command}" ]] || die "run_workspace: missing sub-command" 2
    shift || true

    if [[ "${1-}" == "features-on" || "${1-}" == "features-off" ]]; then
        [[ "${1}" == "features-on" ]] && features=1
        shift || true
    fi
    if [[ "${1-}" == "targets-on" || "${1-}" == "targets-off" ]]; then
        [[ "${1}" == "targets-on" ]] && targets=1
        shift || true
    fi
    if [[ "${1-}" == "deps-on" || "${1-}" == "deps-off" ]]; then
        [[ "${1}" == "deps-off" ]] && no_deps=1
        shift || true
    fi
    if [[ "${1-}" == "all-on" || "${1-}" == "all-off" ]]; then
        [[ "${1}" == "all-on" ]] && all=1
        shift || true
    fi
    if (( workspace )) && [[ "${command}" == "nextest" || "${command}" == "hack" ]]; then
        nested="${1}"
        shift || true
    fi

    for a in "$@"; do

        [[ "${a}" == "--" ]] && break

        case "${a}" in
            -p|--package|--package=*|--manifest-path|--manifest-path=*|--workspace|--all)
                workspace=0
            ;;
        esac
        case "${a}" in
            -F|--features|--features=*|--no-default-features|--all-features)
                features=0
            ;;
        esac
        case "${a}" in
            --lib|--bin|--bin=*|--bins|--example|--example=*|--examples|--test|--test=*|--tests|--bench|--bench=*|--benches|--all-targets)
                targets=0
            ;;
        esac
        case "${a}" in
            --no-deps|--no-deps=*) no_deps=0 ;;
        esac
        case "${a}" in
            --all|--all=*) all=0 ;;
        esac

    done

    (( features )) && extra+=( --all-features )
    (( targets )) && extra+=( --all-targets )
    (( no_deps )) && extra+=( --no-deps )
    (( all )) && extra+=( --all )

    if (( ! workspace || all )); then
        [[ -n "${nested}" ]] &&
            run_cargo "${command}" "${nested}" "${extra[@]}" "$@" ||
            run_cargo "${command}" "${extra[@]}" "$@"
        return 0
    fi

    [[ -n "${nested}" ]] &&
        run_cargo "${command}" "${nested}" --workspace "${extra[@]}" "$@" ||
        run_cargo "${command}" --workspace "${extra[@]}" "$@"

}
run_workspace_publishable () {

    local command="${1:-}" features=0 targets=0 no_deps=0 all=0 workspace=1 a=""
    local -a extra=()

    [[ -n "${command}" ]] || die "run_workspace: missing sub-command" 2
    shift || true

    if [[ "${1-}" == "features-on" || "${1-}" == "features-off" ]]; then
        [[ "${1}" == "features-on" ]] && features=1
        shift || true
    fi
    if [[ "${1-}" == "targets-on" || "${1-}" == "targets-off" ]]; then
        [[ "${1}" == "targets-on" ]] && targets=1
        shift || true
    fi
    if [[ "${1-}" == "deps-on" || "${1-}" == "deps-off" ]]; then
        [[ "${1}" == "deps-off" ]] && no_deps=1
        shift || true
    fi
    if [[ "${1-}" == "all-on" || "${1-}" == "all-off" ]]; then
        [[ "${1}" == "all-on" ]] && all=1
        shift || true
    fi

    for a in "$@"; do

        [[ "${a}" == "--" ]] && break

        case "${a}" in
            -p|--package|--package=*|--manifest-path|--manifest-path=*|--workspace|--all)
                workspace=0
            ;;
        esac
        case "${a}" in
            -F|--features|--features=*|--no-default-features|--all-features)
                features=0
            ;;
        esac
        case "${a}" in
            --lib|--bin|--bin=*|--bins|--example|--example=*|--examples|--test|--test=*|--tests|--bench|--bench=*|--benches|--all-targets)
                targets=0
            ;;
        esac
        case "${a}" in
            --no-deps|--no-deps=*) no_deps=0 ;;
        esac
        case "${a}" in
            --all|--all=*) all=0 ;;
        esac

    done

    (( features )) && extra+=( --all-features )
    (( targets )) && extra+=( --all-targets )
    (( no_deps )) && extra+=( --no-deps )
    (( all )) && extra+=( --all )

    if (( ! workspace || all )); then
        run_cargo "${command}" "${extra[@]}" "$@"
        return 0
    fi

    local -a pkgs=()
    local p=""

    while IFS= read -r p; do [[ -n "${p}" ]] && pkgs+=( --package "${p}" ); done < <(publishable_pkgs)
    (( ${#pkgs[@]} )) || die "No publishable workspace crates found" 2

    run_cargo "${command}" "${pkgs[@]}" "${extra[@]}" "$@"

}
rust_usage () {

    printf '%s\n' \
        '    ensure              Ensure all used crates installed' \
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
        '    spellcheck          Spellcheck docs and text files' \
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
        '    doctor              Show tool versions and optional tooling availability' \
        '    meta                Show workspace metadata (members, names, packages, publishable set)' \
        '    publish             Publish crates in dependency order (workspace publish)' \
        '    yank                Yank a published version (or undo yank)' \
        '' \
        '    ci-stable           CI stable pipeline (check + test + clippy)' \
        '    ci-lint             CI lint pipeline (check-fmt + check-audit + check-taplo + check-prettier + spellcheck)' \
        '    ci-doc              CI docs pipeline (check-doc + test-doc)' \
        '    ci-hack             CI feature-matrix pipeline (cargo-hack)' \
        '    ci-fuzz             CI fuzz pipeline (runs targets with timeout & corpus)' \
        '    ci-coverage         CI coverage pipeline (llvm-cov)' \
        '    ci-msrv             CI MSRV pipeline (check + test --no-run on MSRV toolchain)' \
        '    ci-nightly          CI NIGHTLY pipeline (check + test --no-run on NIGHTLY toolchain)' \
        '    ci-semver           CI SEMVER pipeline (check semver)' \
        '    ci-publish          CI publish gate then publish (full checks + publish)' \
        '' \
        '    ci-local            Run a local CI full workflow ci pipline ( full ci-xxx features )'

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
cmd_clippy () {

    run_workspace_publishable clippy features-on targets-on "$@"

}
cmd_clippy_strict () {

    run_workspace clippy features-on targets-on "$@"

}
cmd_bench () {

    run_workspace bench features-on "$@"

}
cmd_example () {

    source <(parse "$@" -- :name package p)
    run_cargo run -p "${package:-${p:-examples}}" --example "${name}" "${kwargs[@]}"

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
cmd_hack () {

    source <(parse "$@" -- depth:int=2 each_feature:bool)

    if (( each_feature )); then
        run_workspace hack check --keep-going --each-feature "${kwargs[@]}"
        return 0
    fi

    run_workspace hack check --keep-going --feature-powerset --depth "${depth}" "${kwargs[@]}"

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

        [[ -f "${out}" ]] || die "Codecov: file not found: ${out}" 2
        [[ -n "${token}" ]] || token="${CODECOV_TOKEN}"
        [[ -n "${token}" ]] || die "Codecov: CODECOV_TOKEN is missing."

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
cmd_spellcheck () {

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

    local tmp="$(mktemp)"
    local code="$(curl -sSL -o "${tmp}" -w '%{http_code}' "https://index.crates.io/${path}" 2>/dev/null || true)"

    if [[ "${code}" == "404" ]]; then
        rm -f "${tmp}"
        echo "no"
        return 0
    fi
    if [[ "${code}" != "200" ]]; then
        rm -f "${tmp}"
        die "Error: crates.io index request failed for ${name} (HTTP ${code})." 2
    fi
    if grep -q "\"vers\":\"${version}\"" "${tmp}"; then
        rm -f "${tmp}"
        echo "yes"
        return 0
    fi

    rm -f "${tmp}"
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
cmd_doctor () {

    is_ci || { export RUSTFLAGS='-Dwarnings'; export RUST_BACKTRACE='1'; }

    local ok=0 warn=0 fail=0
    local distro="" wsl="no"
    local os="$(uname -s 2>/dev/null || echo unknown)"
    local kernel="$(uname -r 2>/dev/null || echo unknown)"
    local arch="$(uname -m 2>/dev/null || echo unknown)"
    local shell="${SHELL:-unknown}"

    [[ -r /etc/os-release ]] && distro="$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-unknown}")" || distro="unknown"
    [[ -r /proc/version ]] && grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null && wsl="yes"

    local cpu="$(lscpu 2>/dev/null | awk -F: '/Model name/ { sub(/^[ \t]+/,"",$2); print $2; exit }' || true)"
    local cores="$(nproc 2>/dev/null || echo unknown)"
    local mem="$(free -h 2>/dev/null | awk '/^Mem:/ { print $2 " total, " $7 " avail"; exit }' || true)"
    local disk="$(df -h . 2>/dev/null | awk 'NR==2 { print $4 " free of " $2 " (" $5 " used)"; exit }' || true)"

    [[ -n "${cpu}" ]] || cpu="$(awk -F: '/model name/ { sub(/^[ \t]+/,"",$2); print $2; exit }' /proc/cpuinfo 2>/dev/null || true)"
    [[ -n "${cpu}" ]] || cpu="unknown"
    [[ -n "${mem}" ]] || mem="unknown"
    [[ -n "${disk}" ]] || disk="unknown"

    printf '\n=== System ===\n\n'

    printf '  ✅ %-18s %s\n' "OS:" "${os}"; ok=$(( ok + 1 ))
    printf '  ✅ %-18s %s\n' "Distro:" "${distro}"; ok=$(( ok + 1 ))
    printf '  ✅ %-18s %s\n' "Kernel:" "${kernel}"; ok=$(( ok + 1 ))
    printf '  ✅ %-18s %s\n' "Arch:" "${arch}"; ok=$(( ok + 1 ))
    printf '  ✅ %-18s %s\n' "WSL:" "${wsl}"; ok=$(( ok + 1 ))
    printf '  ✅ %-18s %s\n' "Shell:" "${shell}"; ok=$(( ok + 1 ))
    printf '  ✅ %-18s %s\n' "CPU:" "${cpu}"; ok=$(( ok + 1 ))
    printf '  ✅ %-18s %s\n' "Cores:" "${cores}"; ok=$(( ok + 1 ))
    printf '  ✅ %-18s %s\n' "Memory:" "${mem}"; ok=$(( ok + 1 ))
    printf '  ✅ %-18s %s\n' "Disk:" "${disk}"; ok=$(( ok + 1 ))

    printf '\n=== Repo ===\n\n'

    local root="$(pwd 2>/dev/null || echo .)"

    if has git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then

        local branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
        local head="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
        local dirty=""

        if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
            dirty="clean"
        else
            dirty="dirty"
        fi

        printf '  ✅ %-18s %s\n' "Root:" "${root}"; ok=$(( ok + 1 ))
        printf '  ✅ %-18s %s\n' "Branch:" "${branch}"; ok=$(( ok + 1 ))
        printf '  ✅ %-18s %s\n' "Commit:" "${head}"; ok=$(( ok + 1 ))

        if [[ "${dirty}" == "clean" ]]; then
            printf '  ✅ %-18s %s\n' "Status:" "${dirty}"; ok=$(( ok + 1 ))
        else
            printf '  ⚠️ %-18s %s\n' "Status:" "${dirty}"; warn=$(( warn + 1 ))
        fi

    else
        printf '  ✅ %-18s %s\n' "Root:" "${root}"; ok=$(( ok + 1 ))
        printf '  ⚠️ %-18s %s\n' "Git:" "not a git repo"; warn=$(( warn + 1 ))
    fi

    printf '\n=== Tooling ===\n\n'

    if has rustup; then

        local rustc_v="$(rustc -V 2>/dev/null || true)"
        local cargo_v="$(cargo -V 2>/dev/null || true)"
        local active_tc="$(rustup show active-toolchain 2>/dev/null | awk '{print $1}' || true)"
        local stable_tc="${RUST_STABLE:-stable}"
        local nightly_tc="${RUST_NIGHTLY:-nightly}"

        if [[ -n "${rustc_v}" ]]; then
            printf '  ✅ %-18s %s\n' "rustc:" "${rustc_v}"; ok=$(( ok + 1 ))
        else
            printf '  ❌ %-18s %s\n' "rustc:" "missing"; fail=$(( fail + 1 ))
        fi

        if rustup toolchain list 2>/dev/null | awk '{print $1}' | grep -qE "^${stable_tc}(\$|-)"; then
            printf '  ✅ %-18s %s\n' "stable:" "${stable_tc} installed"; ok=$(( ok + 1 ))
        else
            printf '  ⚠️ %-18s %s\n' "stable:" "${stable_tc} missing"; warn=$(( warn + 1 ))
        fi

        if rustup toolchain list 2>/dev/null | awk '{print $1}' | grep -qE "^${nightly_tc}(\$|-)"; then
            printf '  ✅ %-18s %s\n' "nightly:" "${nightly_tc} installed"; ok=$(( ok + 1 ))
        else
            printf '  ⚠️ %-18s %s\n' "nightly:" "${nightly_tc} missing"; warn=$(( warn + 1 ))
        fi

        if [[ -n "${active_tc}" ]]; then
            printf '  ✅ %-18s %s\n' "active:" "${active_tc}"; ok=$(( ok + 1 ))
        else
            printf '  ✅ %-18s %s\n' "active:" "unknown"; ok=$(( ok + 1 ))
        fi

        if [[ -n "${cargo_v}" ]]; then
            printf '  ✅ %-18s %s\n' "cargo:" "${cargo_v}"; ok=$(( ok + 1 ))
        else
            printf '  ❌ %-18s %s\n' "cargo:" "missing"; fail=$(( fail + 1 ))
        fi

    else
        printf '  ❌ %-18s %s\n' "rustup:" "missing"; fail=$(( fail + 1 ))
    fi

    if has clang; then
        printf '  ✅ %-18s %s\n' "clang:" "$(clang --version 2>/dev/null | head -n 1)"; ok=$(( ok + 1 ))
    else
        printf '  ⚠️ %-18s %s\n' "clang:" "missing"; warn=$(( warn + 1 ))
    fi

    if has llvm-config; then
        printf '  ✅ %-18s %s\n' "llvm:" "$(llvm-config --version 2>/dev/null || true)"; ok=$(( ok + 1 ))
    else
        printf '  ⚠️ %-18s %s\n' "llvm:" "missing"; warn=$(( warn + 1 ))
    fi

    if has node; then
        printf '  ✅ %-18s %s\n' "node:" "$(node -v 2>/dev/null || true)"; ok=$(( ok + 1 ))
    else
        printf '  ⚠️ %-18s %s\n' "node:" "missing"; warn=$(( warn + 1 ))
    fi

    if has npx; then
        printf '  ✅ %-18s %s\n' "npx:" "$(npx -v 2>/dev/null || true)"; ok=$(( ok + 1 ))
    else
        printf '  ⚠️ %-18s %s\n' "npx:" "missing"; warn=$(( warn + 1 ))
    fi

    if has npm; then
        printf '  ✅ %-18s %s\n' "npm:" "$(npm -v 2>/dev/null || true)"; ok=$(( ok + 1 ))
    else
        printf '  ⚠️ %-18s %s\n' "npm:" "missing"; warn=$(( warn + 1 ))
    fi

    printf '\n=== Rustup ===\n\n'

    if has rustup; then

        local active_tc="$(rustup show active-toolchain 2>/dev/null | awk '{print $1}' || true)"

        if rustup component list --toolchain "${active_tc}" --installed 2>/dev/null | awk '{print $1}' | grep -qE '^rustfmt($|-)'; then
            printf '  ✅ %-18s %s\n' "rustfmt:" "installed"; ok=$(( ok + 1 ))
        else
            printf '  ⚠️ %-18s %s\n' "rustfmt:" " missing"; warn=$(( warn + 1 ))
        fi

        if rustup component list --toolchain "${active_tc}" --installed 2>/dev/null | awk '{print $1}' | grep -qE '^clippy($|-)'; then
            printf '  ✅ %-18s %s\n' "clippy:" "installed"; ok=$(( ok + 1 ))
        else
            printf '  ⚠️ %-18s %s\n' "clippy:" "missing"; warn=$(( warn + 1 ))
        fi

        if rustup component list --toolchain "${active_tc}" --installed 2>/dev/null | awk '{print $1}' | grep -qE '^(llvm-tools|llvm-tools-preview)($|-)'; then
            printf '  ✅ %-18s %s\n' "llvm-tools:" "installed"; ok=$(( ok + 1 ))
        else
            printf '  ⚠️ %-18s %s\n' "llvm-tools:" "missing"; warn=$(( warn + 1 ))
        fi

        if [[ -n "${RUSTFLAGS:-}" ]]; then
            printf '  ✅ %-18s %s\n' "RUSTFLAGS:" "${RUSTFLAGS}"; ok=$(( ok + 1 ))
        else
            printf '  ⚠️ %-18s %s\n' "RUSTFLAGS:" "not set"; warn=$(( warn + 1 ))
        fi

        if [[ -n "${RUST_BACKTRACE:-}" ]]; then
            printf '  ✅ %-18s %s\n' "RUST_BACKTRACE:" "${RUST_BACKTRACE}"; ok=$(( ok + 1 ))
        else
            printf '  ⚠️ %-18s %s\n' "RUST_BACKTRACE:" "not set"; warn=$(( warn + 1 ))
        fi

    else
        printf '  ❌ %-18s %s\n' "rustup:" "missing"; fail=$(( fail + 1 ))
    fi

    printf '\n=== Cargo ===\n\n'

    if has cargo; then

        has cargo-nextest && { printf '  ✅ %-18s %s\n' "nextest:" "installed"; ok=$(( ok + 1 )); } || { printf '  ⚠️ %-18s %s\n' "nextest:" "missing"; warn=$(( warn + 1 )); }
        has cargo-llvm-cov && { printf '  ✅ %-18s %s\n' "llvm-cov:" "installed"; ok=$(( ok + 1 )); } || { printf '  ⚠️ %-18s %s\n' "llvm-cov:" "missing"; warn=$(( warn + 1 )); }
        has cargo-deny && { printf '  ✅ %-18s %s\n' "cargo-deny:" "installed"; ok=$(( ok + 1 )); } || { printf '  ⚠️ %-18s %s\n' "cargo-deny:" "missing"; warn=$(( warn + 1 )); }
        has cargo-audit && { printf '  ✅ %-18s %s\n' "cargo-audit:" "installed"; ok=$(( ok + 1 )); } || { printf '  ⚠️ %-18s %s\n' "cargo-audit:" "missing"; warn=$(( warn + 1 )); }
        has cargo-semver-checks && { printf '  ✅ %-18s %s\n' "cargo-semver:" "installed"; ok=$(( ok + 1 )); } || { printf '  ⚠️ %-18s %s\n' "cargo-semver:" "missing"; warn=$(( warn + 1 )); }
        has cargo-hack && { printf '  ✅ %-18s %s\n' "cargo-hack:" "installed"; ok=$(( ok + 1 )); } || { printf '  ⚠️ %-18s %s\n' "cargo-hack:" "missing"; warn=$(( warn + 1 )); }
        has cargo-fuzz && { printf '  ✅ %-18s %s\n' "cargo-fuzz:" "installed"; ok=$(( ok + 1 )); } || { printf '  ⚠️ %-18s %s\n' "cargo-fuzz:" "missing"; warn=$(( warn + 1 )); }

        if [[ -d fuzz ]] && [[ -f fuzz/Cargo.toml ]]; then

            local tc="${RUST_NIGHTLY:-nightly}"
            local targets_cnt="0"

            targets_cnt="$(cargo "+${tc}" fuzz list 2>/dev/null | wc -l | tr -d ' ' || true)"
            [[ "${targets_cnt}" =~ ^[0-9]+$ ]] || targets_cnt="0"

            if [[ "${targets_cnt}" -gt 0 ]]; then
                printf '  ✅ %-18s %s\n' "fuzz-targets:" "${targets_cnt}"; ok=$(( ok + 1 ))
            else
                printf '  ⚠️ %-18s %s\n' "fuzz-targets:" "0"; warn=$(( warn + 1 ))
            fi

        fi

    else
        printf '  ❌ %-18s %s\n' "cargo:" "missing"; fail=$(( fail + 1 ))
    fi

    local ok_n="${ok}" warn_n="${warn}" fail_n="${fail}"

    printf '\n=== Summary ===\n\n'
    printf '  ✅ %-18s %s\n' "OK:" "${ok_n}"
    printf '  ⚠️ %-18s %s\n' "Warn:" "${warn_n}"
    printf '  ❌ %-18s %s\n' "Fail:" "${fail_n}"
    printf '\n'

    (( fail_n == 0 )) || return 1
    return 0

}

cmd_ensure () {

    info "Ensure OS Tools ..."
    ensure jq perl grep curl clang llvm-config libclang-dev hunspell awk tail sed sort head wc xargs find git node
    success "OS Tools Installed\n"

    info "Ensure Rustup Tools ..."
    ensure cargo rustfmt clippy llvm-tools-preview
    success "Rustup Tools Installed\n"

    info "Ensure Cargo Tools ..."
    ensure cargo-deny cargo-audit cargo-spellcheck cargo-llvm-cov taplo cargo-nextest cargo-hack cargo-fuzz cargo-ci-cache-clean cargo-semver-checks
    success "Cargo Tools Installed\n"

    trap 'cmd_clean_cache >/dev/null 2>&1 || true' EXIT

}
cmd_ci_stable () {

    cmd_ensure

    info "Check ...\n"
    cmd_check "$@"

    info "Test ...\n"
    cmd_test "$@"

    success "CI STABLE Succeeded.\n"

}
cmd_ci_nightly () {

    cmd_ensure

    info "Check Nightly ...\n"
    cmd_check --nightly "$@"

    info "Test Nightly ...\n"
    cmd_test --nightly "$@"

    success "CI NIGHTLY Succeeded.\n"

}
cmd_ci_msrv () {

    cmd_ensure

    info "Check Msrv ...\n"
    cmd_check --msrv "$@"

    info "Test Msrv ...\n"
    cmd_test --msrv "$@"

    success "CI MSRV Succeeded.\n"

}
cmd_ci_doc () {

    cmd_ensure

    info "Check Doc ...\n"
    cmd_check_doc "$@"

    info "Test Doc ...\n"
    cmd_test_doc "$@"

    success "CI DOC Succeeded.\n"

}
cmd_ci_lint () {

    cmd_ensure

    info "Clippy ...\n"
    cmd_clippy "$@"

    info "Check Audit ...\n"
    cmd_check_audit "$@"

    info "Check Format ...\n"
    cmd_check_fmt "$@"

    info "Check Taplo ...\n"
    cmd_check_taplo "$@"

    info "Check Prettier ...\n"
    cmd_check_prettier "$@"

    info "Check Spellcheck ...\n"
    cmd_spellcheck "$@"

    success "CI LINT Succeeded.\n"

}
cmd_ci_hack () {

    cmd_ensure

    info "Hack ...\n"
    cmd_hack "$@"

    success "CI HACK Succeeded.\n"

}
cmd_ci_fuzz () {

    cmd_ensure

    info "Fuzz ...\n"
    cmd_fuzz "$@"

    success "CI FUZZ Succeeded.\n"

}
cmd_ci_semver () {

    cmd_ensure

    info "Semver ...\n"
    cmd_semver "$@"

    success "CI SEMVER Succeeded.\n"

}
cmd_ci_coverage () {

    cmd_ensure

    info "Coverage ...\n"
    cmd_coverage "$@"

    success "CI Coverage Succeeded.\n"

}
cmd_ci_publish () {

    cmd_ensure

    info "Publish ...\n"
    cmd_publish "$@"

    success "CI PUBLISH Succeeded.\n"

}
cmd_ci_local () {

    cmd_ensure

    info "Check ...\n"
    cmd_check

    info "Test ...\n"
    cmd_test

    info "Check Nightly ...\n"
    cmd_check --nightly

    info "Test Nightly ...\n"
    cmd_test --nightly

    info "Check Msrv ...\n"
    cmd_check --msrv

    info "Test Msrv ...\n"
    cmd_test --msrv

    info "Check Doc ...\n"
    cmd_check_doc

    info "Test Doc ...\n"
    cmd_test_doc

    info "Clippy ...\n"
    cmd_clippy

    info "Check Audit ...\n"
    cmd_check_audit

    info "Check Format ...\n"
    cmd_check_fmt

    info "Check Taplo ...\n"
    cmd_check_taplo

    info "Check Prettier ...\n"
    cmd_check_prettier

    info "Check Spellcheck ...\n"
    cmd_spellcheck

    info "Hack ...\n"
    cmd_hack

    info "Fuzz ...\n"
    cmd_fuzz

    info "Semver ...\n"
    cmd_semver

    info "Coverage ...\n"
    cmd_coverage

    success "CI Pipeline Succeeded.\n"

}
