#!/usr/bin/env bash

codecov_upload () {

    ensure git curl chmod mv mkdir

    local file="${1}"
    local flags="${2:-}"
    local name="${3:-}"
    local version="${4:-latest}"
    local token="${5:-${CODECOV_TOKEN-}}"

    if [[ -z "${token}" ]]; then
        log "Codecov: CODECOV_TOKEN is missing -> skipping upload (common on fork PRs)."
        return 0
    fi

    local os
    local arch
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"

    local dist="linux"
    if [[ "${os}" == "darwin" ]]; then dist="macos"; fi
    if [[ "${dist}" == "linux" && ( "${arch}" == "aarch64" || "${arch}" == "arm64" ) ]]; then dist="linux-arm64"; fi

    [[ -n "${version}" ]] || version="latest"
    [[ -n "${version}" && "${version}" != "latest" && "${version}" != v* ]] && version="v${version}"

    local cache_dir="${ROOT_DIR}/.codecov/cache"
    mkdir -p -- "${cache_dir}"

    local resolved="${version}"

    if [[ "${version}" == "latest" ]]; then

        local latest_page=""
        latest_page="$(curl -fsSL "https://cli.codecov.io/${dist}/latest" 2>/dev/null || true)"

        local v=""
        v="$(printf '%s\n' "${latest_page}" | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"

        [[ -n "${v}" ]] && resolved="${v}"

    fi

    local bin="${cache_dir}/codecov-${dist}-${resolved}"

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

    fi

    run "${bin}" --version >/dev/null 2>&1

    local -a up_args=(
        --verbose
        upload-process
        --disable-search
        --fail-on-error
        -t "${token}"
        -f "${file}"
    )

    [[ -n "${flags}" ]] && up_args+=( -F "${flags}" )
    [[ -n "${name}"  ]] && up_args+=( -n "${name}" )

    run "${bin}" "${up_args[@]}"

    if [[ -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_SHA:-}" ]]; then
        log "Codecov: https://app.codecov.io/gh/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA}"
    fi

}
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

    run_cargo fmt all-on --nightly -- --check "$@"

}
cmd_fix_fmt () {

    run_cargo fmt all-on --nightly "$@"

}
cmd_check_fmt_stable () {

    run_cargo fmt all-on -- --check "$@"

}
cmd_fix_fmt_stable () {

    run_cargo fmt all-on "$@"

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

    ensure cargo

    local name="${1:-}"
    [[ -n "${name}" ]] || die "Usage: example <name> [-p <package>] [-- <args...>]" 2

    shift || true

    local pkg="examples"
    local -a cargo_args=()
    local -a prog_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--package)
                shift || true
                pkg="${1:-}"
                [[ -n "${pkg}" ]] || die "Error: -p/--package requires a value" 2
                shift || true
            ;;
            --package=*)
                pkg="${1#*=}"
                [[ -n "${pkg}" ]] || die "Error: --package requires a value" 2
                shift || true
            ;;
            --)
                shift || true
                prog_args=( "$@" )
                break
            ;;
            *)
                cargo_args+=( "$1" )
                shift || true
            ;;
        esac
    done

    local -a cmd=( run_cargo run -p "${pkg}" --example "${name}" )

    cmd+=( "${cargo_args[@]}" )
    [[ ${#prog_args[@]} -gt 0 ]] && cmd+=( -- "${prog_args[@]}" )

    "${cmd[@]}"

}
cmd_hack () {

    ensure cargo-hack

    local mode="powerset"
    local depth="2"
    local ws=1
    local -a pass=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --each-feature)
                mode="each"
                shift || true
            ;;
            --powerset)
                mode="powerset"
                shift || true
            ;;
            --depth)
                shift || true
                depth="${1:-}"
                [[ -n "${depth}" ]] || die "Error: --depth requires a value" 2
                [[ "${depth}" =~ ^[0-9]+$ ]] || die "Error: --depth must be an integer" 2
                shift || true
            ;;
            -p|--package|--package=*|--manifest-path|--manifest-path=*|--workspace|--workspace=*|--all)
                ws=0
                pass+=( "$1" )
                shift || true
            ;;
            --)
                shift || true
                pass+=( "--" )
                pass+=( "$@" )
                break
            ;;
            *)
                pass+=( "$1" )
                shift || true
            ;;
        esac
    done

    local -a base=( hack check --keep-going )
    (( ws )) && base+=( --workspace )

    if [[ "${mode}" == "each" ]]; then
        run_cargo "${base[@]}" --each-feature "${pass[@]}"
        return $?
    fi

    run_cargo "${base[@]}" --feature-powerset --depth "${depth}" "${pass[@]}"

}
cmd_fuzz () {

    ensure cargo awk grep

    local tc
    tc="$(tool_nightly_version)"
    rustup toolchain list 2>/dev/null | awk '{print $1}' | grep -qx "${tc}" || run rustup toolchain install "${tc}" --profile minimal

    local timeout="10" len="4096"
    local have_max_total_time=0 have_max_len=0 in_post=0
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
        done < <(cargo +"${tc}" fuzz list 2>/dev/null || true)

        [[ "${#targets[@]}" -gt 0 ]] || die "No fuzz targets found. Run: cargo +${tc} fuzz init && cargo +${tc} fuzz add <name>" 2

        local t=""
        for t in "${targets[@]}"; do
            if [[ "${#post[@]}" -gt 0 ]]; then
                run cargo +"${tc}" fuzz run "${t}" "${pre[@]}" -- "${post[@]}" || die "Fuzzing failed: ${t}" 2
            else
                run cargo +"${tc}" fuzz run "${t}" "${pre[@]}" || die "Fuzzing failed: ${t}" 2
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
        run cargo +"${tc}" fuzz "${pre[@]}" -- "${post[@]}"
        return $?
    fi

    run cargo +"${tc}" fuzz "${pre[@]}"

}
cmd_semver () {

    ensure cargo-semver-checks git

    local remote="${GIT_REMOTE:-origin}"
    local baseline="${CARGO_SEMVER_CHECKS_BASELINE_REV:-${SEMVER_BASELINE:-}}"

    if [[ "${1:-}" == --baseline=* ]]; then
        baseline="${1#*=}"
        shift || true
    elif [[ "${1:-}" == "--baseline" ]]; then
        shift || true
        baseline="${1:-}"
        [[ -n "${baseline}" ]] || die "semver: --baseline requires a value" 2
        shift || true
    fi

    if [[ -z "${baseline}" ]]; then

        if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]; then

            local base="${GITHUB_BASE_REF:-}"
            [[ -n "${base}" ]] || die "semver: missing GITHUB_BASE_REF. Provide --baseline <rev>." 2

            run git fetch --no-tags "${remote}" "${base}:refs/remotes/${remote}/${base}" >/dev/null 2>&1 || \
                die "semver: failed to fetch ${remote}/${base}. Provide --baseline <rev>." 2

            baseline="${remote}/${base}"

        elif [[ "${GITHUB_EVENT_NAME:-}" == "push" && "${GITHUB_REF_TYPE:-}" == "tag" && "${GITHUB_REF_NAME:-}" == v* ]]; then

            run git fetch --tags --force --prune "${remote}" >/dev/null 2>&1 || true

            local cur="${GITHUB_REF_NAME}"

            baseline="$(
                git tag --list 'v*' --sort=-v:refname |
                grep -E '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' |
                grep -F -x -v -- "${cur}" |
                head -n 1 || true
            )"

            if [[ -z "${baseline}" ]]; then
                log "semver: first stable release (no previous vMAJOR.MINOR.PATCH tag). Skipping."
                return 0
            fi

        else

            local def=""
            def="$(git symbolic-ref -q "refs/remotes/${remote}/HEAD" 2>/dev/null || true)"
            def="${def#refs/remotes/${remote}/}"
            [[ -n "${def}" ]] || def="main"

            run git fetch --no-tags "${remote}" "${def}:refs/remotes/${remote}/${def}" >/dev/null 2>&1 || true

            if git show-ref --verify --quiet "refs/remotes/${remote}/${def}"; then
                baseline="${remote}/${def}"
            else
                log "semver: no baseline branch found (${remote}/${def}). Skipping."
                return 0
            fi

        fi
    fi

    [[ -n "${baseline}" ]] || { log "semver: no baseline. Skipping."; return 0; }
    git rev-parse --verify "${baseline}^{commit}" >/dev/null 2>&1 || die "semver: baseline '${baseline}' is not a valid commit/tag." 2

    export CARGO_SEMVER_CHECKS_BASELINE_REV="${baseline}"
    log "semver: baseline=${baseline}"

    local -a extra=()

    if run_cargo semver-checks -h 2>/dev/null | grep -q -- '--baseline-rev'; then
        extra+=(--baseline-rev "${baseline}")
    fi

    run_cargo semver-checks "${extra[@]}" "$@"

}
cmd_coverage () {

    ensure cargo jq

    local upload=0
    local codecov_name=""
    local codecov_token=""
    local codecov_version=""
    local codecov_flags=""
    local mode="lcov"

    local -a want_pkgs=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --upload)
                upload=1
                shift
            ;;
            --mode)
                [[ -n "${2-}" ]] || die "Missing value for --mode" 2
                mode="${2}"
                shift 2
            ;;
            -p|--package)
                [[ -n "${2-}" ]] || die "Missing value for ${1}" 2
                want_pkgs+=( "${2}" )
                shift 2 || true
            ;;
            --package=*)
                [[ -n "${1#*=}" ]] || die "Missing value for --package" 2
                want_pkgs+=( "${1#*=}" )
                shift
            ;;
            --name)
                codecov_name="${2-}"
                shift 2 || true
            ;;
            --flags)
                codecov_flags="${2-}"
                shift 2 || true
            ;;
            --version)
                codecov_version="${2-}"
                shift 2 || true
            ;;
            --token)
                codecov_token="${2-}"
                shift 2 || true
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
    case "${mode}" in
        lcov|json|codecov) ;;
        *) die "Invalid --mode: ${mode} (use: lcov|json|codecov)" 2 ;;
    esac

    if ! run_cargo llvm-cov --version >/dev/null 2>&1; then
        log "cargo-llvm-cov is not installed."
        log "Install:"
        log "  rustup component add llvm-tools"
        log "  cargo install cargo-llvm-cov"
        exit 2
    fi
    if has rustup; then
        if ! run rustup component list --installed 2>/dev/null | grep -Eq '^(llvm-tools|llvm-tools-preview)\b'; then
            log "Missing Rust component: llvm-tools (or llvm-tools-preview)"
            log "Install one of:"
            log "  rustup component add llvm-tools"
            log "  rustup component add llvm-tools-preview"
            exit 2
        fi
    fi

    local -a pkgs=()

    if [[ ${#want_pkgs[@]} -gt 0 ]]; then

        local -a ws_pkgs=()
        mapfile -t ws_pkgs < <(cargo metadata --no-deps --format-version 1 2>/dev/null | jq -r '.packages[].name')

        local -A ws_set=()
        local -A seen=()
        local x="" p=""

        for x in "${ws_pkgs[@]-}"; do
            ws_set["${x}"]=1
        done
        for p in "${want_pkgs[@]-}"; do
            [[ -n "${ws_set[${p}]-}" ]] || die "Unknown workspace package: ${p}" 2
            [[ -n "${seen[${p}]-}" ]] && continue
            seen["${p}"]=1
            pkgs+=( "${p}" )
        done

        [[ ${#pkgs[@]} -gt 0 ]] || die "No packages selected" 2

    else

        while IFS= read -r line; do pkgs+=( "${line}" ); done < <(publishable_pkgs)
        [[ ${#pkgs[@]} -gt 0 ]] || die "No publishable workspace crates found" 2

    fi

    local args=()
    local p=""

    for p in "${pkgs[@]-}"; do
        args+=( -p "${p}" )
    done

    local out="${ROOT_DIR}/lcov.info"

    if [[ "${mode}" == "codecov" ]]; then

        out="${ROOT_DIR}/codecov.json"
        run_cargo llvm-cov "${args[@]}" --all-targets --all-features --codecov --output-path "${out}" "$@"

    elif [[ "${mode}" == "json" ]]; then

        out="${ROOT_DIR}/coverage.json"
        run_cargo llvm-cov "${args[@]}" --all-targets --all-features --json --output-path "${out}" "$@"

    else

        run_cargo llvm-cov "${args[@]}" --all-targets --all-features --lcov --output-path "${out}" "$@"

    fi

    if (( upload )); then

        if [[ -z "${codecov_name}" ]]; then

            if [[ ${#pkgs[@]} -eq 1 ]]; then
                codecov_name="coverage-${pkgs[0]}"
            else
                codecov_name="coverage-${GITHUB_RUN_ID:-local}"
            fi

        fi
        if [[ -z "${codecov_flags}" ]]; then

            if [[ ${#pkgs[@]} -eq 1 ]]; then
                codecov_flags="${pkgs[0]}"
            else
                codecov_flags="crates"
            fi

        fi

        codecov_upload "${out}" "${codecov_flags}" "${codecov_name}" "${codecov_version}" "${codecov_token}"

    fi

    log "OK -> ${out}"

}
cmd_spellcheck () {

    ensure cargo head sed wc sort grep xargs

    if ! run_cargo spellcheck --version >/dev/null 2>&1; then
        log "cargo-spellcheck is not installed."
        log "Install: cargo install cargo-spellcheck"
        exit 2
    fi

    local file="${ROOT_DIR}/spellcheck.dic"
    ensure_file "${file}"

    local first_line
    first_line="$(head -n 1 "${file}" || true)"

    if ! [[ "${first_line}" =~ ^[0-9]+$ ]]; then
        die "Error: The first line of ${file} must be an integer word count, got: '${first_line}'" 2
    fi

    local expected_count="${first_line}"
    local actual_count
    actual_count="$(sed '1d' "${file}" | wc -l | xargs)"

    local sort_locale="$(tool_pick_sort_locale)"
    local paths=("$@")

    if [[ "${expected_count}" != "${actual_count}" ]]; then
        die "Error: Word count mismatch. Expected ${expected_count}, got ${actual_count}." 2
    fi
    if ! ( sed '1d' "${file}" | LC_ALL="${sort_locale}" sort -uc ) >/dev/null; then
        log "Dictionary is not sorted or has duplicates. Correct order is:"
        LC_ALL="${sort_locale}" sort -u <(sed '1d' "${file}")
        exit 1
    fi
    if [[ ${#paths[@]} -eq 0 ]]; then
        shopt -s nullglob
        paths=( * )
        shopt -u nullglob
    fi

    run_cargo spellcheck --code 1 "${paths[@]}"

    if grep -I --exclude-dir=.git --exclude-dir=target --exclude-dir=scripts -nRE '[[:blank:]]+$' .; then
        die "Please remove trailing whitespace from these lines." 1
    fi

    log "All matching files use a correct spell-checking format."

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
cmd_check_taplo () {

    ensure taplo
    run taplo fmt --check "$@"

}
cmd_fix_taplo () {

    ensure taplo
    run taplo fmt "$@"

}
cmd_check_audit () {

    ensure cargo-deny
    run_cargo deny check advisories bans licenses sources "$@"

}
cmd_fix_audit () {

    ensure cargo-audit

    local adv="${HOME}/.cargo/advisory-db"

    if [[ -d "${adv}" ]] && [[ ! -d "${adv}/.git" ]]; then
        mv "${adv}" "${adv}.broken.$(date +%s)" || true
    fi

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
cmd_doctor () {

    ensure

    is_ci || {
        export RUSTFLAGS='-Dwarnings'
        export RUST_BACKTRACE='1'
    }

    local ok=0 warn=0 fail=0
    local distro="" wsl="no" ci="no"
    local os="$(uname -s 2>/dev/null || echo unknown)"
    local kernel="$(uname -r 2>/dev/null || echo unknown)"
    local arch="$(uname -m 2>/dev/null || echo unknown)"
    local shell="${SHELL:-unknown}"

    [[ -r /etc/os-release ]] && distro="$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-unknown}")" || distro="unknown"
    [[ -r /proc/version ]] && grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null && wsl="yes"
    [[ -n "${GITHUB_ACTIONS:-}" || -n "${CI:-}" ]] && ci="yes"

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
    printf '  ✅ %-18s %s\n' "CI:" "${ci}"; ok=$(( ok + 1 ))
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
cmd_meta () {

    ensure cargo jq

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
        ensure tee
        run_cargo metadata "${cargo_args[@]}" | tee "${out}" | jq "${jq_args[@]}" "${filter}"
        return 0
    fi

    run_cargo metadata "${cargo_args[@]}" | jq "${jq_args[@]}" "${filter}"

}
cmd_version () {

    ensure cargo jq

    local name="${1:-}"
    local meta=""

    meta="$(cargo metadata --no-deps --format-version 1)" || die "Error: failed to read cargo metadata." 2

    if [[ -z "${name}" ]]; then

        local ws_root="" root_manifest=""
        ws_root="$(jq -r '.workspace_root' <<<"${meta}")"
        root_manifest="${ws_root}/Cargo.toml"

        local v=""
        v="$(jq -r --arg m "${root_manifest}" '
            .packages[] | select(.manifest_path == $m) | .version
        ' <<<"${meta}" 2>/dev/null || true)"

        if [[ -z "${v}" || "${v}" == "null" ]]; then

            local id=""
            id="$(jq -r '.workspace_members[0]' <<<"${meta}")"

            v="$(jq -r --arg id "${id}" '
                .packages[] | select(.id == $id) | .version
            ' <<<"${meta}")"

        fi

        [[ -n "${v}" && "${v}" != "null" ]] || die "Error: workspace version not found." 2

        printf '%s\n' "${v}"
        return 0

    fi

    local v=""
    v="$(jq -r --arg n "${name}" '
        .packages[] | select(.name == $n) | .version
    ' <<<"${meta}" 2>/dev/null | head -n 1)"

    [[ -n "${v}" && "${v}" != "null" ]] || die "Error: package ${name} not found." 2

    printf '%s\n' "${v}"

}
cmd_is_publishable () {

    ensure grep tr

    local name="${1:-}" needle=""
    [[ -n "${name}" ]] || die "Error: package name is required." 2

    needle="$(printf '%s' "${name}" | tr '[:upper:]' '[:lower:]')"

    if publishable_pkgs | tr '[:upper:]' '[:lower:]' | grep -Fxq -- "${needle}"; then
        printf '%s\n' "yes"
        return 0
    fi

    printf '%s\n' "no"
    return 1

}
cmd_is_published () {

    ensure grep curl

    local name="${1:-}"
    [[ -n "${name}" ]] || die "Error: crate name is required." 2
    [[ "$(cmd_is_publishable "${name}")" == "yes" ]] || die "Error: package ${name} is not publishable." 2

    local version=""
    version="$(cmd_version "${name}")"

    local name_lc="${name,,}"
    local n="${#name_lc}"
    local path=""

    if (( n == 1 )); then path="1/${name_lc}"
    elif (( n == 2 )); then path="2/${name_lc}"
    elif (( n == 3 )); then path="3/${name_lc:0:1}/${name_lc}"
    else path="${name_lc:0:2}/${name_lc:2:2}/${name_lc}"; fi

    local tmp=""
    tmp="$(mktemp)"

    local code=""
    code="$(curl -sSL -o "${tmp}" -w '%{http_code}' "https://index.crates.io/${path}" 2>/dev/null || true)"

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

    ensure

    local name="${1:-}"

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

    ensure cargo

    local dry_run=0
    local allow_dirty=0
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
            --allow-dirty)
                allow_dirty=1
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

    [[ ${#packages[@]} -gt 0 && ${#excludes[@]} -gt 0 ]] && die "Error: --exclude cannot be used with --package/-p" 2
    local p="" env_token="${CARGO_REGISTRY_TOKEN:-}"

    for p in "${packages[@]}"; do
        [[ "${p}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "Error: invalid package name: ${p}" 2
    done
    for p in "${excludes[@]}"; do
        [[ "${p}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "Error: invalid exclude name: ${p}" 2
    done

    [[ -n "${token}" && "${token}" =~ [[:space:]] ]] && die "Error: --token contains whitespace (looks invalid)." 2
    [[ -n "${env_token}" && "${env_token}" =~ [[:space:]] ]] && die "Error: CARGO_REGISTRY_TOKEN contains whitespace (looks invalid)." 2

    if is_ci && (( dry_run == 0 )); then

        if [[ "${GITHUB_EVENT_NAME:-}" != "push" || "${GITHUB_REF:-}" != refs/tags/v* ]]; then
            die "Refusing publish in CI (need tag push: refs/tags/v*)." 2
        fi

        [[ -n "${token}" || -n "${env_token}" ]] || die "Missing registry token in CI. Use --token <...> or set CARGO_REGISTRY_TOKEN." 2

    fi
    if (( dry_run == 0 )) && has git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then

        if (( allow_dirty == 0 )) && [[ -n "$(git status --porcelain --untracked-files=normal 2>/dev/null)" ]]; then
            die "Refusing publish with a dirty git working tree. Commit/stash changes, or pass --allow-dirty." 2
        fi

    fi
    if (( dry_run == 0 )) && [[ -z "${token}" && -z "${env_token}" ]]; then
        die "Missing publish token. Use --token <...> or set CARGO_REGISTRY_TOKEN." 2
    fi

    (( dry_run )) && cargo_args+=( --dry-run )
    local i=0

    while [[ $i -lt ${#excludes[@]} ]]; do
        cargo_args+=( --exclude "${excludes[$i]}" )
        i=$(( i + 1 ))
    done

    if (( dry_run == 0 )) && ! is_ci; then

        local msg="About to publish "

        if [[ ${#packages[@]} -gt 0 ]]; then
            msg+="package(s): ${packages[*]}"
        else
            msg+="workspace"
            [[ ${#excludes[@]} -gt 0 ]] && msg+=" (exclude: ${excludes[*]})"
        fi

        confirm "${msg}. Continue?" || die "Aborted." 1

    fi

    local old_token="" old_token_set=0 xtrace=0

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

    if [[ ${#packages[@]} -gt 0 ]]; then

        for p in "${packages[@]}"; do
            [[ "$(cmd_can_publish "${p}")" == "yes" ]] || die "Error: ${p} already published" 2
        done
        for p in "${packages[@]}"; do
            run_cargo publish --package "${p}" "${cargo_args[@]}" "$@"
        done

    else

        [[ "$(cmd_can_publish)" == "yes" ]] || die "Error: there is one/many packages already published" 2
        run_cargo publish --workspace "${cargo_args[@]}" "$@"

    fi

}
cmd_yank () {

    ensure cargo

    local package=""
    local version=""
    local undo=0
    local token=""
    local env_token="${CARGO_REGISTRY_TOKEN:-}"
    local -a pass=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--package)
                shift || true
                package="${1:-}"
                [[ -n "${package}" ]] || die "Error: -p/--package requires a value" 2
                shift || true
            ;;
            --package=*)
                package="${1#*=}"
                [[ -n "${package}" ]] || die "Error: --package requires a value" 2
                shift || true
            ;;
            -V|--version)
                shift || true
                version="${1:-}"
                [[ -n "${version}" ]] || die "Error: --version requires a value" 2
                shift || true
            ;;
            --version=*)
                version="${1#*=}"
                [[ -n "${version}" ]] || die "Error: --version requires a value" 2
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
            --undo|--restore)
                undo=1
                shift || true
            ;;
            --)
                shift || true
                pass+=( "$@" )
                break
            ;;
            -*)
                pass+=( "$1" )
                shift || true
            ;;
            *)
                if [[ -z "${package}" ]]; then
                    package="$1"
                    shift || true
                    continue
                fi
                if [[ -z "${version}" ]]; then
                    version="$1"
                    shift || true
                    continue
                fi
                die "Unknown arg: $1 (use -- to pass extra args)" 2
            ;;
        esac
    done

    [[ -n "${package}" ]] || die "Error: missing package. Use -p/--package." 2
    [[ -n "${version}" ]] || die "Error: missing version. Use --version." 2

    version="${version#v}"

    [[ "${package}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "Error: invalid package name: ${package}" 2
    [[ "${version}" =~ ^[0-9][0-9A-Za-z.+-]*$ ]] || die "Error: invalid version: ${version}" 2
    [[ -n "${token}" && "${token}" =~ [[:space:]] ]] && die "Error: --token contains whitespace (looks invalid)." 2
    [[ -n "${env_token}" && "${env_token}" =~ [[:space:]] ]] && die "Error: CARGO_REGISTRY_TOKEN contains whitespace (looks invalid)." 2

    if is_ci; then

        if [[ "${GITHUB_EVENT_NAME:-}" != "push" || "${GITHUB_REF:-}" != refs/tags/v* ]]; then
            die "Refusing yank in CI (need tag push: refs/tags/v*)." 2
        fi

        [[ -n "${token}" || -n "${env_token}" ]] || die "Missing registry token in CI. Use --token <...> or set CARGO_REGISTRY_TOKEN." 2

    fi

    local action="yank" old_token="" old_token_set=0 xtrace=0
    (( undo )) && action="undo yank"

    if ! is_ci; then
        confirm "About to ${action} ${package} v${version}. Continue?" || die "Aborted." 1
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
        run_cargo yank -p "${package}" --version "${version}" --undo "${pass[@]}"
        return 0
    fi

    run_cargo yank -p "${package}" --version "${version}" "${pass[@]}"

}

cmd_ensure () {

    into "\nEnsure OS Tools ... \n"
    ensure jq perl grep curl clang llvm-config libclang-dev hunspell awk tail sed sort head wc xargs find git node
    success "\nOS Tools Installed \n\n"

    info "\nEnsure Rustup Tools ... \n"
    ensure cargo rustfmt clippy llvm-tools-preview
    success "\nRustup Tools Installed \n\n"

    info "\nEnsure Cargo Tools ... \n"
    ensure cargo-deny cargo-audit cargo-spellcheck cargo-llvm-cov taplo cargo-nextest cargo-hack cargo-fuzz cargo-ci-cache-clean cargo-semver-checks
    success "\nCargo Tools Installed \n\n"

    trap 'cmd_clean_cache >/dev/null 2>&1 || true' EXIT

}
cmd_ci_stable () {

    cmd_ensure

    printf "\n💥 Check ...\n\n"
    cmd_check "$@"

    printf "\n💥 Test ...\n\n"
    cmd_test "$@"

    printf "\n✅ CI STABLE Succeeded.\n\n"

}
cmd_ci_nightly () {

    cmd_ensure

    printf "\n💥 Check Nightly ...\n\n"
    cmd_check --nightly "$@"

    printf "\n💥 Test Nightly ...\n\n"
    cmd_test --nightly "$@"

    printf "\n✅ CI NIGHTLY Succeeded.\n\n"

}
cmd_ci_msrv () {

    cmd_ensure

    printf "\n💥 Check Msrv ...\n\n"
    cmd_check --msrv "$@"

    printf "\n💥 Test Msrv ...\n\n"
    cmd_test --msrv "$@"

    printf "\n✅ CI MSRV Succeeded.\n\n"

}
cmd_ci_doc () {

    cmd_ensure

    printf "\n💥 Check Doc ...\n\n"
    cmd_check_doc "$@"

    printf "\n💥 Test Doc ...\n\n"
    cmd_test_doc "$@"

    printf "\n✅ CI DOC Succeeded.\n\n"

}
cmd_ci_lint () {

    cmd_ensure

    printf "\n💥 Clippy ...\n\n"
    cmd_clippy "$@"

    printf "\n💥 Check Audit ...\n\n"
    cmd_check_audit "$@"

    printf "\n💥 Check Format ...\n\n"
    cmd_check_fmt --nightly "$@"

    printf "\n💥 Check Taplo ...\n\n"
    cmd_check_taplo "$@"

    printf "\n💥 Check Prettier ...\n\n"
    cmd_check_prettier "$@"

    printf "\n💥 Check Spellcheck ...\n\n"
    cmd_spellcheck "$@"

    printf "\n✅ CI LINT Succeeded.\n\n"

}
cmd_ci_hack () {

    cmd_ensure

    printf "\n💥 Hack ...\n\n"
    cmd_hack "$@"

    printf "\n✅ CI HACK Succeeded.\n\n"

}
cmd_ci_fuzz () {

    cmd_ensure

    printf "\n💥 Fuzz ...\n\n"
    cmd_fuzz "$@"

    printf "\n✅ CI FUZZ Succeeded.\n\n"

}
cmd_ci_semver () {

    cmd_ensure

    printf "\n💥 Semver ...\n\n"
    cmd_semver "$@"

    printf "\n✅ CI SEMVER Succeeded.\n\n"

}
cmd_ci_coverage () {

    cmd_ensure

    printf "\n💥 Coverage ...\n\n"
    cmd_coverage "$@"

    printf "\n✅ CI Coverage Succeeded.\n\n"

}
cmd_ci_publish () {

    cmd_ensure

    printf "\n💥 Publish ...\n\n"
    cmd_publish "$@"

    printf "\n✅ CI PUBLISH Succeeded.\n\n"

}
cmd_ci_local () {

    cmd_ensure

    printf "\n💥 Check ...\n\n"
    cmd_check

    printf "\n💥 Test ...\n\n"
    cmd_test

    printf "\n💥 Check Nightly ...\n\n"
    cmd_check --nightly

    printf "\n💥 Test Nightly ...\n\n"
    cmd_test --nightly

    printf "\n💥 Check Msrv ...\n\n"
    cmd_check --msrv

    printf "\n💥 Test Msrv ...\n\n"
    cmd_test --msrv

    printf "\n💥 Check Doc ...\n\n"
    cmd_check_doc

    printf "\n💥 Test Doc ...\n\n"
    cmd_test_doc

    printf "\n💥 Clippy ...\n\n"
    cmd_clippy

    printf "\n💥 Check Audit ...\n\n"
    cmd_check_audit

    printf "\n💥 Check Format ...\n\n"
    cmd_check_fmt --nightly

    printf "\n💥 Check Taplo ...\n\n"
    cmd_check_taplo

    printf "\n💥 Check Prettier ...\n\n"
    cmd_check_prettier

    printf "\n💥 Check Spellcheck ...\n\n"
    cmd_spellcheck

    printf "\n💥 Hack ...\n\n"
    cmd_hack

    printf "\n💥 Fuzz ...\n\n"
    cmd_fuzz

    printf "\n💥 Semver ...\n\n"
    cmd_semver

    printf "\n💥 Coverage ...\n\n"
    cmd_coverage

    printf "\n✅ CI Pipeline Succeeded.\n\n"

}
