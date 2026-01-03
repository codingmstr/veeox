#!/usr/bin/env bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base.sh"

docflags_deny () {

    local cur="${RUSTDOCFLAGS:-}"

    [[ "${cur}" == *"-Dwarnings"* ]] && { printf '%s' "${cur}"; return 0; }
    [[ -n "${cur}" ]] && { printf '%s -Dwarnings' "${cur}"; return 0; }

    printf '%s' "-Dwarnings"

}
pick_sort_locale () {

    local all=""

    if has_cmd locale; then
        all="$(locale -a 2>/dev/null || true)"

        printf '%s\n' "${all}" | grep -qx "C\.UTF-8"     && { printf '%s\n' "C.UTF-8"; return 0; }
        printf '%s\n' "${all}" | grep -qx "en_US\.UTF-8" && { printf '%s\n' "en_US.UTF-8"; return 0; }
    fi

    printf '%s\n' "C"

}
pick_sort_bin () {

    local c=""

    for c in sort /usr/bin/sort gsort; do

        command -v "${c}" >/dev/null 2>&1 || continue

        LC_ALL=C "${c}" -V </dev/null >/dev/null 2>&1 && {
            printf '%s\n' "${c}"
            return 0
        }

    done

    die "Need a sort that supports -V (GNU sort). Install coreutils (gsort)." 2

}
sort_ver () {

    local loc="$(pick_sort_locale)"
    local sbin="$(pick_sort_bin)"

    LC_ALL="${loc}" "${sbin}" -V

}
sort_uniq () {

    local loc="$(pick_sort_locale)"
    local sbin="$(pick_sort_bin)"

    LC_ALL="${loc}" "${sbin}" -u

}
normalize_version () {

    local tc="${1}"
    tc="${tc#v}"

    case "${tc}" in
        stable|beta|nightly) printf '%s\n' "${tc}"; return 0 ;;
        nightly-????-??-??)  printf '%s\n' "${tc}"; return 0 ;;
    esac

    [[ "${tc}" =~ ^[0-9]+\.[0-9]+$ ]] && tc="${tc}.0"
    [[ "${tc}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Error: invalid version: ${1}" 2

    printf '%s\n' "${tc}"

}
stable_version () {

    normalize_version "${RUST_STABLE:-stable}"

}
nightly_version () {

    normalize_version "${RUST_NIGHTLY:-nightly}"

}
msrv_version () {

    need_cmd cargo
    need_cmd rustc
    need_cmd jq
    need_cmd tail
    need_cmd awk
    need_cmd sed

    local tc=""

    if [[ -n "${RUST_MSRV:-}" ]]; then

        tc="$(normalize_version "${RUST_MSRV}")"
        [[ "${tc}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Error: invalid RUST_MSRV (need x.y.z): ${RUST_MSRV}" 2

        printf '%s\n' "${tc}"
        return 0

    fi

    local want="$(cargo metadata --no-deps --format-version 1 2>/dev/null | jq -r '.packages[].rust_version // empty' | sort_ver | tail -n 1)"
    local have="$(rustc -V | awk '{print $2}' | sed 's/[^0-9.].*$//')"

    [[ -n "${want}" ]] || { printf '%s\n' "${have}"; return 0; }

    tc="$(normalize_version "${want}")"
    [[ "${tc}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Error: invalid workspace rust_version (need x.y.z): ${want}" 2

    [[ "$(printf '%s\n%s\n' "${tc}" "${have}" | sort_ver | awk 'NR==1{print;exit}')" == "${tc}" ]] || die "Rust too old: need >= ${tc}, have ${have}" 2
    printf '%s\n' "${tc}"

}
ensure_toolchain () {

    local tc="${1:-}"
    [[ -n "${tc}" ]] || die "Error: ensure_toolchain needs a toolchain" 2

    need_cmd rustup

    rustup run "${tc}" rustc -V >/dev/null 2>&1 && return 0

    run rustup toolchain install "${tc}" --profile minimal
    rustup run "${tc}" rustc -V >/dev/null 2>&1 || die "rustc not working after install: ${tc}" 2

}
ensure_rust () {

    need_cmd uname

    local stable="" nightly="" msrv="" uname_s=""

    stable="$(stable_version)"
    nightly="$(nightly_version)"
    uname_s="$(uname -s 2>/dev/null || true)"

    export PATH="${HOME}/.cargo/bin:${PATH}"

    if [[ -n "${GITHUB_PATH:-}" ]]; then
        printf '%s\n' "${HOME}/.cargo/bin" >> "${GITHUB_PATH}"
    fi

    if ! has_cmd rustup; then

        need_cmd curl
        need_cmd sh

        case "${uname_s}" in
            MINGW*|MSYS*|CYGWIN*)

                local tmp="${TMPDIR:-${TEMP:-/tmp}}/rustup-init.$$.exe"

                run curl -fsSL -o "${tmp}" "https://win.rustup.rs/x86_64" || die "Failed to download rustup-init.exe" 2
                run "${tmp}" -y --profile minimal --default-toolchain "${stable}" || die "Failed to install rustup (Windows)" 2
                rm -f -- "${tmp}" 2>/dev/null || true

            ;;
            Darwin|Linux)

                run curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
                    | sh -s -- -y --profile minimal --default-toolchain "${stable}" \
                    || die "Failed to install rustup." 2

            ;;
            *)

                die "Unsupported OS for rustup install: ${uname_s}" 2

            ;;
        esac

        export PATH="${HOME}/.cargo/bin:${PATH}"
        [[ -f "${HOME}/.cargo/env" ]] && source "${HOME}/.cargo/env" || true

        has_cmd rustup || die "rustup installed but not found in PATH (check ~/.cargo/bin)." 2

    fi

    msrv="$( ( msrv_version ) 2>/dev/null || true )"
    [[ -n "${msrv}" ]] || msrv="${stable}"

    ensure_toolchain "${stable}"
    ensure_toolchain "${nightly}"
    ensure_toolchain "${msrv}"

    run rustup run "${stable}"  cargo -V >/dev/null 2>&1 || die "cargo (stable) not working after install." 2
    run rustup run "${nightly}" rustc -V >/dev/null 2>&1 || die "rustc (nightly) not working after install." 2
    run rustup run "${msrv}"    rustc -V >/dev/null 2>&1 || die "rustc (msrv) not working after install." 2

    if is_ci; then
        run rustup default "${stable}"
    fi

}
ensure_component () {

    local comp="${1:-}"
    local tc="${2:-}"

    [[ -n "${comp}" ]] || die "Error: ensure_component requires a component name" 2
    has_cmd rustup || return 0

    if [[ -z "${tc}" ]]; then
        tc="$(stable_version)"
    fi

    ensure_toolchain "${tc}"

    if [[ "${comp}" == "llvm-tools-preview" ]]; then

        rustup +"${tc}" component list --installed 2>/dev/null | grep -qE '^(llvm-tools|llvm-tools-preview)\b' && return 0

        run rustup +"${tc}" component add llvm-tools-preview 2>/dev/null || run rustup +"${tc}" component add llvm-tools
        return 0

    fi

    rustup +"${tc}" component list --installed 2>/dev/null | grep -qE "^${comp}\b" && return 0
    run rustup +"${tc}" component add "${comp}"

}
ensure_crate () {

    local crate="${1:-}"
    local bin="${2:-}"

    [[ -n "${crate}" ]] || die "Error: ensure_crate requires <crate>" 2
    [[ -n "${bin}" ]]   || die "Error: ensure_crate requires <bin>" 2
    shift 2

    export PATH="${HOME}/.cargo/bin:${PATH}"

    if has_cmd "${bin}"; then
        return 0
    fi

    run cargo install --locked "${crate}" "$@" || die "Failed to install: ${crate}" 2
    has_cmd "${bin}" || die "Installed ${crate} but '${bin}' not found in PATH (check ~/.cargo/bin)." 2

}
ensure_node () {

    local want="${1:-24}" v major uname_s=""
    uname_s="$(uname -s 2>/dev/null || true)"

    if has_cmd node; then

        v="$(node --version 2>/dev/null || true)"
        v="${v#v}"
        major="${v%%.*}"

        [[ "${major}" =~ ^[0-9]+$ ]] || die "Can't parse Node.js version: ${v}" 2

        if (( major >= want )) && has_cmd npx && npx --version >/dev/null 2>&1; then
            return 0
        fi

    fi

    if [[ "${uname_s}" =~ ^(MINGW|MSYS|CYGWIN) ]]; then

        local u=""
        u="${USERNAME:-$(whoami 2>/dev/null || true)}"

        if [[ -d "/c/Users/${u}/AppData/Local/Volta" ]]; then
            export VOLTA_HOME="/c/Users/${u}/AppData/Local/Volta"
        else
            export VOLTA_HOME="${HOME}/.volta"
        fi

    else

        export VOLTA_HOME="${VOLTA_HOME:-${HOME}/.volta}"

    fi

    export PATH="${VOLTA_HOME}/bin:${PATH}"

    if ! has_cmd volta; then

        case "${uname_s}" in
            MINGW*|MSYS*|CYGWIN*)

                if has_cmd winget; then
                    run winget install -e --id Volta.Volta --accept-package-agreements --accept-source-agreements --silent
                elif has_cmd choco; then
                    run choco install -y volta
                else
                    die "No installer found (need winget or choco) to install Volta on Windows." 2
                fi

                export PATH="/c/ProgramData/chocolatey/bin:${PATH}"

                if ! has_cmd volta; then
                    local u=""
                    u="${USERNAME:-$(whoami 2>/dev/null || true)}"

                    local p1="/c/Users/${u}/AppData/Local/Volta/bin"
                    local p2="/c/Users/${u}/.volta/bin"

                    [[ -d "${p1}" ]] && export PATH="${p1}:${PATH}"
                    [[ -d "${p2}" ]] && export PATH="${p2}:${PATH}"
                fi

            ;;
            *)
                ensure_pkg --no-update curl
                run curl -fsSL https://get.volta.sh | bash || die "Failed to install Volta." 2
            ;;
        esac

        export PATH="${VOLTA_HOME}/bin:${PATH}"
        has_cmd volta || die "Volta installed but not found in PATH. Restart shell or fix PATH/VOLTA_HOME." 2

    fi

    run volta install "node@${want}" || die "Failed to install Node via Volta." 2

    has_cmd node || die "Node install finished but 'node' not found in PATH." 2
    has_cmd npx  || die "npx not found after Node install. Check PATH/VOLTA_HOME." 2
    npx --version >/dev/null 2>&1 || die "npx exists but failed to run. Check environment/PATH." 2

    v="$(node --version 2>/dev/null || true)"
    v="${v#v}"
    major="${v%%.*}"

    [[ "${major}" =~ ^[0-9]+$ ]] || die "Can't parse Node.js version after install: ${v}" 2
    (( major >= want )) || die "Node install did not satisfy requirement (need ${want}+, found v${v})." 2

    if [[ -n "${GITHUB_PATH:-}" ]]; then
        printf '%s\n' "${VOLTA_HOME}/bin" >> "${GITHUB_PATH}"
    fi

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
        | sort_uniq

}
codecov_upload () {

    local file="${1}"
    local flags="${2:-}"
    local name="${3:-}"
    local version="${4:-latest}"
    local token="${5:-${CODECOV_TOKEN-}}"

    need_cmd git
    need_cmd curl
    need_cmd chmod
    need_cmd mv
    need_cmd mkdir

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

    local cache_dir="${ROOT_DIR}/.vx/cache"
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
cargo_run () {

    need_cmd cargo

    local sub="${1:-}" tc="" mode="stable"
    [[ -n "${sub}" ]] || die "Error: cargo_run requires a cargo subcommand (example: cargo_run check ...)" 2
    shift || true

    local use_plus=0 need_docflags=0
    local -a pass=()

    has_cmd rustup && use_plus=1

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
            tc="$(nightly_version)"
        elif [[ "${mode}" == "msrv" ]]; then
            tc="$(msrv_version)"
        else
            tc="$(stable_version)"
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
        if (( use_plus )); then
            RUSTDOCFLAGS="$(docflags_deny)" run cargo +"${tc}" "${sub}" "${pass[@]}"
            return $?
        fi

        RUSTDOCFLAGS="$(docflags_deny)" run cargo "${sub}" "${pass[@]}"
        return $?
    fi
    if (( use_plus )); then
        run cargo +"${tc}" "${sub}" "${pass[@]}"
        return $?
    fi

    run cargo "${sub}" "${pass[@]}"

}
cargo_help () {

    cat <<'OUT'
    ensure              Ensure all vx used crates installed
    new                 Create a new crate and (optionally) add it to the workspace
    build               Build the whole workspace, or a single crate if specified
    run                 Run a binary (use -p/--package to pick a crate, or pass a bin name)

    check               Run compile checks for all crates and targets (no binaries produced)
    test                Run the full test suite (workspace-wide or a single crate)
    hack                Run feature matrix checks using cargo-hack (each-feature or powerset)
    fuzz                Run fuzz targets to find crashes/panics (uses cargo-fuzz)
    semver              Run cargo semver checks using cargo-semver-checks
    bench               Run benchmarks (workspace-wide or a single crate)
    example             Run an example target by name, forwarding extra args after --
    clean               Remove build artifacts

    msrv                Get the latest minimum support rust version in all crates, return (env.RUST_MSRV if exists)
    msrv-check          Validate that your Rust compiler satisfies the workspace checks msrv
    msrv-test           Validate that your Rust compiler satisfies the workspace tests msrv
    nightly-check       Validate that your Rust compiler satisfies the workspace checks nightly version
    nightly-test        Validate that your Rust compiler satisfies the workspace tests nightly version

    fix-ws              Remove trailing whitespace in git-tracked files
    check-fmt           Verify formatting (no changes)
    fix-fmt             Auto-format code
    check-fmt-nightly   Verify formatting checks --nightly (no changes)
    fix-fmt-nightly     Auto-format code --nightly

    clippy              Run lints on crates/ only (strict)
    clippy-strict       Run lints on the full workspace (very strict)

    spellcheck          Spellcheck docs and text files
    coverage            Generate coverage reports (lcov + codecov json)

    check-audit         Security advisory checks (policy gate)
    fix-audit           Apply automatic dependency upgrades to address advisories

    check-prettier      Validate formatting for Markdown/YAML/etc. (no changes)
    fix-prettier        Auto-format Markdown/YAML/etc.

    check-taplo         Validate TOML formatting (no changes)
    fix-taplo           Auto-format TOML files

    check-doc           Build docs strictly (workspace or single crate)
    test-doc            Run documentation tests (doctests)
    open-doc            Build docs then open them in your browser

    doctor              Show tool versions and optional tooling availability
    meta                Show workspace metadata (members, names, packages, publishable set)
    publish             Publish crates in dependency order (workspace publish)
    yank                Yank a published version (or undo yank)

    ci-stable           CI stable pipeline (check + test + clippy)
    ci-lint             CI lint pipeline (check-fmt + check-audit + check-taplo + check-prettier + spellcheck)
    ci-doc              CI docs pipeline (check-doc + test-doc)
    ci-hack             CI feature-matrix pipeline (cargo-hack)
    ci-fuzz             CI fuzz pipeline (runs targets with timeout & corpus)
    ci-coverage         CI coverage pipeline (llvm-cov)
    ci-msrv             CI MSRV pipeline (check + test --no-run on MSRV toolchain)
    ci-nightly          CI NIGHTLY pipeline (check + test --no-run on NIGHTLY toolchain)
    ci-semver           CI SEMVER pipeline (check semver)
    ci-publish          CI publish gate then publish (full checks + publish)

    ci-local            Run a local CI full workflow ci pipline ( full ci-xxx features )
OUT
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
                shift || true
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
    [[ "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "Error: invalid crate name: ${name}" 2

    local path="${dir}/${name}"
    [[ -e "${path}" ]] && die "Error: already exists: ${path}" 2

    mkdir -p -- "${dir}" 2>/dev/null || true
    cargo_run new --vcs none "${kind}" "${pass[@]}" "${path}"

    [[ ${add_workspace} -eq 1 ]] || return 0
    [[ -f Cargo.toml ]] || return 0

    grep -qF "\"${dir}/${name}\"" Cargo.toml 2>/dev/null && return 0

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

    local add_ws=1
    local -a pass=( "$@" )

    local i=0
    while (( i < ${#pass[@]} )); do
        case "${pass[i]}" in
            -p|--package|--package=*|--manifest-path|--manifest-path=*|--workspace|--workspace=*|--all)
                add_ws=0
                break
            ;;
        esac
        (( i++ ))
    done

    (( add_ws )) && cargo_run build --workspace "${pass[@]}" || cargo_run build "${pass[@]}"

}
cmd_run () {

    cd_root
    need_cmd cargo

    local pkg="" bin=""
    local -a cargo_args=()
    local -a prog_args=()
    local -a cmd=()

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
            --bin)
                shift || true
                bin="${1:-}"
                [[ -n "${bin}" ]] || die "Error: --bin requires a value" 2
                shift || true
            ;;
            --bin=*)
                bin="${1#*=}"
                [[ -n "${bin}" ]] || die "Error: --bin requires a value" 2
                shift || true
            ;;
            --)
                shift || true
                prog_args=( "$@" )
                break
            ;;
            -*)
                cargo_args+=( "$1" )
                shift || true
            ;;
            *)
                if [[ -z "${bin}" ]]; then
                    bin="$1"
                    shift || true
                else
                    die "Error: program args must come after -- (example: vx run ${bin} -- --arg)" 2
                fi
            ;;
        esac
    done

    cmd=( cargo_run run )

    [[ -n "${pkg}" ]] && cmd+=( -p "${pkg}" )
    [[ -n "${bin}" ]] && cmd+=( --bin "${bin}" )

    cmd+=( "${cargo_args[@]}" )
    [[ ${#prog_args[@]} -gt 0 ]] && cmd+=( -- "${prog_args[@]}" )

    "${cmd[@]}"

}
cmd_clean () {

    cd_root
    need_cmd cargo

    cargo_run clean "$@"

}
cmd_clean_cache () {

    cd_root
    need_cmd cargo
    need_cmd cargo-ci-cache-clean

    cargo_run ci-cache-clean "$@"

}
cmd_check () {

    cd_root
    need_cmd cargo

    local ws=1

    for a in "$@"; do
        case "${a}" in
            -p|--package|--package=*|--manifest-path|--manifest-path=*|--workspace|--workspace=*|--all)
                ws=0
                break
            ;;
        esac
    done

    (( ws )) && cargo_run check --workspace --all-targets --all-features "$@" || cargo_run check --all-targets --all-features "$@"

}
cmd_test () {

    cd_root
    need_cmd cargo

    local package=""
    local ws=1
    local want_all_features=1
    local -a pass=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--package)
                shift || true
                package="${1:-}"
                [[ -n "${package}" ]] || die "Error: -p/--package requires a value" 2
                [[ "${package}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "Error: invalid package name: ${package}" 2
                ws=0
                shift || true
            ;;
            --package=*)
                package="${1#*=}"
                [[ -n "${package}" ]] || die "Error: --package requires a value" 2
                [[ "${package}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "Error: invalid package name: ${package}" 2
                ws=0
                shift || true
            ;;
            --manifest-path|--manifest-path=*|--workspace|--workspace=*|--all)
                ws=0
                pass+=( "$1" )
                shift || true
            ;;
            --features|--features=*|--no-default-features)
                want_all_features=0
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

    local -a feat=()
    (( want_all_features )) && feat=( --all-features )

    if cargo nextest --version >/dev/null 2>&1; then

        if [[ -n "${package}" ]]; then
            cargo_run nextest run -p "${package}" "${feat[@]}" "${pass[@]}"
            return 0
        fi

        (( ws )) \
            && cargo_run nextest run --workspace "${feat[@]}" "${pass[@]}" \
            || cargo_run nextest run "${feat[@]}" "${pass[@]}"

        return 0

    fi
    if has_cmd cargo-nextest; then

        local -a cmd=( cargo-nextest run )

        [[ -n "${package}" ]] && cmd+=( -p "${package}" )
        (( ws )) && cmd+=( --workspace )

        cmd+=( "${feat[@]}" )
        cmd+=( "${pass[@]}" )

        run "${cmd[@]}"
        return 0

    fi
    if [[ -n "${package}" ]]; then
        cargo_run test -p "${package}" "${feat[@]}" "${pass[@]}"
        return 0
    fi

    (( ws )) && cargo_run test --workspace "${feat[@]}" "${pass[@]}" || cargo_run test "${feat[@]}" "${pass[@]}"

}
cmd_check_doc () {

    cd_root
    need_cmd cargo

    local ws=1

    for a in "$@"; do
        case "${a}" in
            -p|--package|--package=*|--manifest-path|--manifest-path=*|--workspace|--workspace=*|--all)
                ws=0
                break
            ;;
        esac
    done

    (( ws )) && cargo_run doc --workspace --all-features --no-deps "$@" || cargo_run doc --all-features --no-deps "$@"

}
cmd_test_doc () {

    cd_root
    need_cmd cargo

    local ws=1

    for a in "$@"; do
        case "${a}" in
            -p|--package|--package=*|--manifest-path|--manifest-path=*|--workspace|--workspace=*|--all)
                ws=0
                break
            ;;
        esac
    done

    (( ws )) && cargo_run test --workspace --all-features --doc "$@" || cargo_run test --all-features --doc "$@"

}
cmd_open_doc () {

    cd_root
    need_cmd cargo

    local ws=1
    for a in "$@"; do
        case "${a}" in
            -p|--package|--package=*|--manifest-path|--manifest-path=*|--workspace|--workspace=*|--all)
                ws=0
                break
            ;;
        esac
    done

    (( ws )) && cargo_run doc --workspace --all-features --no-deps "$@" || cargo_run doc --all-features --no-deps "$@"
    local index=""

    if [[ -f "${ROOT_DIR}/target/doc/index.html" ]]; then
        index="${ROOT_DIR}/target/doc/index.html"
    else
        index="$(find "${ROOT_DIR}/target/doc" -maxdepth 2 -name index.html -print | head -n 1 || true)"
    fi

    [[ -n "${index}" && -f "${index}" ]] || die "Docs index not found under target/doc" 2
    open_path "${index}"

}
cmd_clean_doc () {

    cd_root
    local p="${ROOT_DIR}/target/doc"

    [[ -d "${p}" ]] || return 0
    rm -rf -- "${p}" || die "Failed to remove: ${p}" 2

}
cmd_check_fmt () {

    cd_root
    need_cmd cargo
    need_cmd rustfmt

    cargo_run fmt --all --check "$@"

}
cmd_fix_fmt () {

    cd_root
    need_cmd cargo
    need_cmd rustfmt

    cargo_run fmt --all "$@"

}
cmd_check_fmt_nightly () {

    cmd_check_fmt --nightly

}
cmd_fix_fmt_nightly () {

    cmd_fix_fmt --nightly

}
cmd_clippy () {

    cd_root
    need_cmd cargo

    local has_sel=0
    local a=""

    for a in "$@"; do
        case "${a}" in
            -p|--package|--package=*|--manifest-path|--manifest-path=*|--workspace|--workspace=*)
                has_sel=1
                break
            ;;
        esac
    done

    if (( has_sel )); then
        cargo_run clippy --all-targets --all-features "$@"
        return 0
    fi

    local -a pkgs=()
    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        pkgs+=( "${line}" )
    done < <(only_publish_pkgs)

    [[ ${#pkgs[@]} -gt 0 ]] || die "No publishable workspace crates found" 2

    local -a args=()
    local p=""
    for p in "${pkgs[@]-}"; do
        args+=( -p "${p}" )
    done

    cargo_run clippy "${args[@]}" --all-targets --all-features "$@"

}
cmd_clippy_strict () {

    cd_root
    need_cmd cargo

    cargo_run clippy --workspace --all-targets --all-features "$@"

}
cmd_bench () {

    cd_root
    need_cmd cargo

    local ws=1
    local want_all_features=1
    local -a pass=()

    for a in "$@"; do
        case "${a}" in
            -p|--package|--package=*|--manifest-path|--manifest-path=*|--workspace|--workspace=*|--all)
                ws=0
                break
            ;;
        esac
    done
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --features|--features=*|--no-default-features)
                want_all_features=0
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

    local -a feat=()
    (( want_all_features )) && feat=( --all-features )

    (( ws )) && cargo_run bench --workspace "${feat[@]}" "${pass[@]}" || cargo_run bench "${feat[@]}" "${pass[@]}"

}
cmd_example () {

    cd_root
    need_cmd cargo

    local name="${1:-}"
    [[ -n "${name}" ]] || die "Usage: vx example <name> [-p <package>] [-- <args...>]" 2

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

    local -a cmd=( cargo_run run -p "${pkg}" --example "${name}" )

    cmd+=( "${cargo_args[@]}" )
    [[ ${#prog_args[@]} -gt 0 ]] && cmd+=( -- "${prog_args[@]}" )

    "${cmd[@]}"

}
cmd_hack () {

    cd_root
    need_cmd cargo
    need_cmd cargo-hack

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
        cargo_run "${base[@]}" --each-feature "${pass[@]}"
        return $?
    fi

    cargo_run "${base[@]}" --feature-powerset --depth "${depth}" "${pass[@]}"

}
cmd_fuzz () {

    cd_root
    need_cmd cargo
    need_cmd rustup
    need_cmd awk
    need_cmd grep

    local tc
    tc="$(nightly_version)"
    rustup toolchain list 2>/dev/null | awk '{print $1}' | grep -qx "${tc}" || run rustup toolchain install "${tc}" --profile minimal

    local timeout="15" len="4096"
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

    cd_root
    need_cmd git
    need_cmd cargo
    need_cmd cargo-semver-checks

    local remote="${VX_GIT_REMOTE:-origin}"
    local baseline="${CARGO_SEMVER_CHECKS_BASELINE_REV:-${VX_SEMVER_BASELINE:-}}"

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
                grep -vx "${cur}" |
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

    if cargo_run semver-checks -h 2>/dev/null | grep -q -- '--baseline-rev'; then
        extra+=(--baseline-rev "${baseline}")
    fi

    cargo_run semver-checks "${extra[@]}" "$@"

}
cmd_coverage () {

    cd_root
    need_cmd cargo
    need_cmd jq

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

    if ! cargo_run llvm-cov --version >/dev/null 2>&1; then
        log "cargo-llvm-cov is not installed."
        log "Install:"
        log "  rustup component add llvm-tools"
        log "  cargo install cargo-llvm-cov"
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

        while IFS= read -r line; do pkgs+=( "${line}" ); done < <(only_publish_pkgs)
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
        cargo_run llvm-cov "${args[@]}" --all-targets --all-features --codecov --output-path "${out}" "$@"

    elif [[ "${mode}" == "json" ]]; then

        out="${ROOT_DIR}/coverage.json"
        cargo_run llvm-cov "${args[@]}" --all-targets --all-features --json --output-path "${out}" "$@"

    else

        cargo_run llvm-cov "${args[@]}" --all-targets --all-features --lcov --output-path "${out}" "$@"

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

    cd_root
    need_cmd cargo
    need_cmd head
    need_cmd sed
    need_cmd wc
    need_cmd sort
    need_cmd grep
    need_cmd xargs

    if ! cargo_run spellcheck --version >/dev/null 2>&1; then
        log "cargo-spellcheck is not installed."
        log "Install: cargo install cargo-spellcheck"
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

    local sort_locale="$(pick_sort_locale)"
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

    cargo_run spellcheck --code 1 "${paths[@]}"

    if grep -I --exclude-dir=.git --exclude-dir=target --exclude-dir=scripts -nRE '[[:blank:]]+$' .; then
        die "Please remove trailing whitespace from these lines." 1
    fi

    log "All matching files use a correct spell-checking format."

}
cmd_check_prettier () {

    cd_root
    has_cmd node || { is_ci && die "node is required for prettier" 2; log "skip: node not installed"; return 0; }
    has_cmd npx  || { is_ci && die "npx is required for prettier" 2; log "skip: npx not installed"; return 0; }

    run npx -y prettier@3.3.3 --no-error-on-unmatched-pattern --check \
        ".github/**/*.{yml,yaml}" \
        "**/*.md" \
        ".prettierrc.yml" \
        "$@"

}
cmd_fix_prettier () {

    cd_root
    has_cmd node || { is_ci && die "node is required for prettier" 2; log "skip: node not installed"; return 0; }
    has_cmd npx  || { is_ci && die "npx is required for prettier" 2; log "skip: npx not installed"; return 0; }

    run npx -y prettier@3.3.3 --no-error-on-unmatched-pattern --write \
        ".github/**/*.{yml,yaml}" \
        "**/*.md" \
        ".prettierrc.yml" \
        "$@"

}
cmd_check_taplo () {

    cd_root
    need_cmd taplo
    run taplo fmt --check "$@"

}
cmd_fix_taplo () {

    cd_root
    need_cmd taplo
    run taplo fmt "$@"

}
cmd_check_audit () {

    cd_root
    need_cmd cargo
    need_cmd cargo-deny
    cargo_run deny check advisories bans licenses sources "$@"

}
cmd_fix_audit () {

    cd_root
    need_cmd cargo
    need_cmd cargo-audit

    local adv="${HOME}/.cargo/advisory-db"

    if [[ -d "${adv}" ]] && [[ ! -d "${adv}/.git" ]]; then
        mv "${adv}" "${adv}.broken.$(date +%s)" || true
    fi

    cargo_run audit fix "$@"

}
cmd_fix_ws () {

    cd_root
    need_cmd git
    need_cmd perl

    local f=""

    while IFS= read -r -d '' f; do

        perl -0777 -ne 'exit 1 if /\0/; exit 0' -- "${f}" 2>/dev/null || continue
        perl -0777 -i -pe 's/[ \t]+$//mg if /[ \t]+$/m' -- "${f}"

    done < <(git ls-files -z)

}
cmd_doctor () {

    cd_root

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

    if has_cmd git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then

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

    if has_cmd rustup; then

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

    if has_cmd clang; then
        printf '  ✅ %-18s %s\n' "clang:" "$(clang --version 2>/dev/null | head -n 1)"; ok=$(( ok + 1 ))
    else
        printf '  ⚠️ %-18s %s\n' "clang:" "missing"; warn=$(( warn + 1 ))
    fi

    if has_cmd llvm-config; then
        printf '  ✅ %-18s %s\n' "llvm:" "$(llvm-config --version 2>/dev/null || true)"; ok=$(( ok + 1 ))
    else
        printf '  ⚠️ %-18s %s\n' "llvm:" "missing"; warn=$(( warn + 1 ))
    fi

    if has_cmd node; then
        printf '  ✅ %-18s %s\n' "node:" "$(node -v 2>/dev/null || true)"; ok=$(( ok + 1 ))
    else
        printf '  ⚠️ %-18s %s\n' "node:" "missing"; warn=$(( warn + 1 ))
    fi

    if has_cmd npx; then
        printf '  ✅ %-18s %s\n' "npx:" "$(npx -v 2>/dev/null || true)"; ok=$(( ok + 1 ))
    else
        printf '  ⚠️ %-18s %s\n' "npx:" "missing"; warn=$(( warn + 1 ))
    fi

    if has_cmd npm; then
        printf '  ✅ %-18s %s\n' "npm:" "$(npm -v 2>/dev/null || true)"; ok=$(( ok + 1 ))
    else
        printf '  ⚠️ %-18s %s\n' "npm:" "missing"; warn=$(( warn + 1 ))
    fi

    printf '\n=== Rustup ===\n\n'

    if has_cmd rustup; then

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

    if has_cmd cargo; then

        has_cmd cargo-nextest && { printf '  ✅ %-18s %s\n' "nextest:" "installed"; ok=$(( ok + 1 )); } || { printf '  ⚠️ %-18s %s\n' "nextest:" "missing"; warn=$(( warn + 1 )); }
        has_cmd cargo-llvm-cov && { printf '  ✅ %-18s %s\n' "llvm-cov:" "installed"; ok=$(( ok + 1 )); } || { printf '  ⚠️ %-18s %s\n' "llvm-cov:" "missing"; warn=$(( warn + 1 )); }
        has_cmd cargo-deny && { printf '  ✅ %-18s %s\n' "cargo-deny:" "installed"; ok=$(( ok + 1 )); } || { printf '  ⚠️ %-18s %s\n' "cargo-deny:" "missing"; warn=$(( warn + 1 )); }
        has_cmd cargo-audit && { printf '  ✅ %-18s %s\n' "cargo-audit:" "installed"; ok=$(( ok + 1 )); } || { printf '  ⚠️ %-18s %s\n' "cargo-audit:" "missing"; warn=$(( warn + 1 )); }
        has_cmd cargo-semver-checks && { printf '  ✅ %-18s %s\n' "cargo-semver:" "installed"; ok=$(( ok + 1 )); } || { printf '  ⚠️ %-18s %s\n' "cargo-semver:" "missing"; warn=$(( warn + 1 )); }
        has_cmd cargo-hack && { printf '  ✅ %-18s %s\n' "cargo-hack:" "installed"; ok=$(( ok + 1 )); } || { printf '  ⚠️ %-18s %s\n' "cargo-hack:" "missing"; warn=$(( warn + 1 )); }
        has_cmd cargo-fuzz && { printf '  ✅ %-18s %s\n' "cargo-fuzz:" "installed"; ok=$(( ok + 1 )); } || { printf '  ⚠️ %-18s %s\n' "cargo-fuzz:" "missing"; warn=$(( warn + 1 )); }

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
        cargo_run metadata "${cargo_args[@]}" | tee "${out}" | jq "${jq_args[@]}" "${filter}"
        return 0
    fi

    cargo_run metadata "${cargo_args[@]}" | jq "${jq_args[@]}" "${filter}"

}
cmd_version () {

    cd_root
    need_cmd cargo
    need_cmd jq

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

    need_cmd grep
    need_cmd tr

    local name="${1:-}" needle=""
    [[ -n "${name}" ]] || die "Error: package name is required." 2

    needle="$(printf '%s' "${name}" | tr '[:upper:]' '[:lower:]')"

    if only_publish_pkgs | tr '[:upper:]' '[:lower:]' | grep -Fxq -- "${needle}"; then
        printf '%s\n' "yes"
        return 0
    fi

    printf '%s\n' "no"
    return 1

}
cmd_is_published () {

    cd_root
    need_cmd curl
    need_cmd grep

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

    cd_root

    local name="${1:-}"

    if [[ -n "${name}" ]]; then

        [[ "$(cmd_is_published "${name}")" == "yes" ]] && { echo "no"; return 0; }

        echo "yes"
        return 0

    fi

    local p=""

    local -a pkgs=()
    while IFS= read -r line; do pkgs+=( "${line}" ); done < <(only_publish_pkgs)
    [[ ${#pkgs[@]} -gt 0 ]] || { echo "no"; return 0; }

    for p in "${pkgs[@]}"; do
        [[ "$(cmd_is_published "${p}")" == "yes" ]] && { echo "no"; return 0; }
    done

    echo "yes"

}
cmd_publish () {

    cd_root
    need_cmd cargo

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
    if (( dry_run == 0 )) && has_cmd git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then

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
            cargo_run publish --package "${p}" "${cargo_args[@]}" "$@"
        done

    else

        [[ "$(cmd_can_publish)" == "yes" ]] || die "Error: there is one/many packages already published" 2
        cargo_run publish --workspace "${cargo_args[@]}" "$@"

    fi

}
cmd_yank () {

    cd_root
    need_cmd cargo

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
            -h|--help)
                log "Usage:"
                log "    vx yank -p <crate> --version <x.y.z> [--undo] [--token <...>] [-- <extra cargo args>]"
                return 0
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
        cargo_run yank -p "${package}" --version "${version}" --undo "${pass[@]}"
        return 0
    fi

    cargo_run yank -p "${package}" --version "${version}" "${pass[@]}"

}

cmd_ensure () {

    cd_root

    printf "\n💥 Ensure OS Tools ... \n\n"

    ensure_pkg --no-update jq perl grep curl clang llvm-dev libclang-dev hunspell awk tail sed sort head wc xargs find git
    ensure_rust
    ensure_node

    printf "\n💥 Ensure rustup Tools ... \n\n"

    ensure_component rustfmt
    ensure_component clippy
    ensure_component llvm-tools-preview

    printf "\n💥 Ensure Cargo Tools ... \n\n"

    ensure_crate cargo-deny            cargo-deny
    ensure_crate cargo-audit           cargo-audit --features fix
    ensure_crate cargo-spellcheck      cargo-spellcheck
    ensure_crate cargo-llvm-cov        cargo-llvm-cov
    ensure_crate taplo-cli             taplo
    ensure_crate cargo-nextest         cargo-nextest
    ensure_crate cargo-hack            cargo-hack
    ensure_crate cargo-fuzz            cargo-fuzz
    ensure_crate cargo-ci-cache-clean  cargo-ci-cache-clean
    ensure_crate cargo-semver-checks   cargo-semver-checks

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
    # cmd_publish "$@"

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
