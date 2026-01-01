#!/usr/bin/env bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base.sh"

ensure_rust () {

    local tc="${1:-stable}"
    local uname_s=""

    export PATH="${HOME}/.cargo/bin:${PATH}"

    if [[ -n "${GITHUB_PATH:-}" ]]; then
        printf '%s\n' "${HOME}/.cargo/bin" >> "${GITHUB_PATH}"
    fi

    has_cmd rustup && {

        rustup which rustc >/dev/null 2>&1 || {
            run rustup toolchain install "${tc}" --profile minimal
            run rustup default "${tc}"
        }

        return 0

    }

    uname_s="$(uname -s 2>/dev/null || true)"

    need_cmd curl

    case "${uname_s}" in
        MINGW*|MSYS*|CYGWIN*)
            local tmp="${TMPDIR:-${TEMP:-/tmp}}/rustup-init.$$.exe"

            run curl -fsSL -o "${tmp}" "https://win.rustup.rs/x86_64" || die "Failed to download rustup-init.exe" 2
            run "${tmp}" -y --profile minimal --default-toolchain "${tc}" || die "Failed to install rustup (Windows)" 2
            rm -f -- "${tmp}" 2>/dev/null || true
        ;;
        Darwin|Linux)
            run curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
                | sh -s -- -y --profile minimal --default-toolchain "${tc}" \
                || die "Failed to install rustup." 2
        ;;
        *)
            return 0
        ;;
    esac

    export PATH="${HOME}/.cargo/bin:${PATH}"
    [[ -f "${HOME}/.cargo/env" ]] && source "${HOME}/.cargo/env" || true

    has_cmd rustup || die "rustup installed but not found in PATH (check ~/.cargo/bin)." 2

    run rustup toolchain install "${tc}" --profile minimal
    is_ci && run rustup default "${tc}"

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
ensure_component () {

    local comp="${1}"

    has_cmd rustup || return 0

    if [[ "${comp}" == "llvm-tools-preview" ]]; then

        if rustup component list --installed 2>/dev/null | grep -qE '^(llvm-tools|llvm-tools-preview)\b'; then
            return 0
        fi

        run rustup component add llvm-tools-preview 2>/dev/null || run rustup component add llvm-tools
        return 0

    fi
    if rustup component list --installed 2>/dev/null | grep -qE "^${comp}\b"; then
        return 0
    fi

    run rustup component add "${comp}"

}
ensure_crate () {

    local crate="${1}"
    local bin="${2}"

    shift 2

    export PATH="${HOME}/.cargo/bin:${PATH}"
    has_cmd "${bin}" && return 0

    run cargo install "${crate}" "$@" || die "Failed to install: ${crate}" 2
    has_cmd "${bin}" || die "Installed ${crate} but '${bin}' not found in PATH (check ~/.cargo/bin)." 2

}
docflags_deny () {

    local cur="${RUSTDOCFLAGS:-}"

    if [[ -n "${cur}" ]]; then
        printf '%s -Dwarnings' "${cur}"
        return 0
    fi

    printf '%s' "-Dwarnings"

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
cargo_help () {

    cat <<'OUT'
    ensure           Ensure all vx used crates installed
    new              Create a new crate and (optionally) add it to the workspace
    build            Build the whole workspace, or a single crate if specified
    run              Run a binary (use -p/--package to pick a crate, or pass a bin name)

    check            Fast compile checks for all crates and targets (no binaries produced)
    test             Run the full test suite (workspace-wide or a single crate)
    hack             Run feature matrix checks using cargo-hack (each-feature or powerset)
    semver           Run cargo semver checks using cargo-semver-checks
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

    meta             Show workspace metadata (members, names, packages, publishable set)
    publish          Publish crates in dependency order (workspace publish)
    yank             Yank a published version (or undo yank)

    ci-fast          CI fast pipeline (check + test + clippy)
    ci-fmt           CI format pipeline (check-fmt + check-audit + check-taplo + check-prettier + spellcheck)
    ci-doc           CI docs pipeline (check-doc + test-doc)
    ci-hack          CI feature-matrix pipeline (cargo-hack)
    ci-coverage      CI coverage pipeline (llvm-cov)
    ci-msrv          CI MSRV pipeline (check + test --no-run on MSRV toolchain)
    ci-semver        CI SEMVER pipeline (check semver)
    ci-publish       CI publish gate then publish (full checks + publish)
    ci-local         Run a local CI full workflow ci pipline (checks + tests + fmts + hack + doc + semver + coverage)
OUT
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
    run cargo new --vcs none "${kind}" "${pass[@]}" "${path}"

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
            --bin)
                shift || true
                bin="${1:-}"
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

    local -a cmd=( cargo run )

    [[ -n "${pkg}" ]] && cmd+=( -p "${pkg}" )
    [[ -n "${bin}" ]] && cmd+=( --bin "${bin}" )

    cmd+=( "${cargo_args[@]}" )
    [[ ${#prog_args[@]} -gt 0 ]] && cmd+=( -- "${prog_args[@]}" )

    run "${cmd[@]}"

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
        perl -0777 -ne 'exit 1 if /\0/; exit 0' "${f}" 2>/dev/null || continue
        perl -0777 -i -pe 's/[ \t]+$//mg if /[ \t]+$/m' "${f}"
    done < <(git ls-files -z)

}
cmd_check_fmt () {

    cd_root
    need_cmd cargo

    if has_cmd rustup; then
        ensure_component rustfmt
    else
        need_cmd rustfmt
    fi

    run cargo fmt --all --check "$@"

}
cmd_fix_fmt () {

    cd_root
    need_cmd cargo

    if has_cmd rustup; then
        ensure_component rustfmt
    else
        need_cmd rustfmt
    fi

    run cargo fmt --all "$@"

}
cmd_check_doc () {

    cd_root
    need_cmd cargo

    local flags=""
    flags="$(docflags_deny)"

    if [[ $# -eq 0 ]]; then
        RUSTDOCFLAGS="${flags}" run cargo doc --workspace --all-features --no-deps
        return 0
    fi
    if [[ "${1:-}" == "-p" || "${1:-}" == "--package" ]]; then

        shift || true

        local package="${1:-}"
        [[ -n "${package}" ]] || die "Error: -p/--package requires a value" 2

        shift || true

        RUSTDOCFLAGS="${flags}" run cargo doc -p "${package}" --all-features --no-deps "$@"
        return 0

    fi

    RUSTDOCFLAGS="${flags}" run cargo doc --workspace --all-features --no-deps "$@"

}
cmd_test_doc () {

    cd_root
    need_cmd cargo

    local flags=""
    flags="$(docflags_deny)"

    if [[ $# -eq 0 ]]; then
        RUSTDOCFLAGS="${flags}" run cargo test --workspace --all-features --doc
        return 0
    fi
    if [[ "${1:-}" == "-p" || "${1:-}" == "--package" ]]; then

        shift || true

        local package="${1:-}"
        [[ -n "${package}" ]] || die "Error: -p/--package requires a value" 2

        shift || true

        RUSTDOCFLAGS="${flags}" run cargo test -p "${package}" --all-features --doc "$@"
        return 0

    fi

    RUSTDOCFLAGS="${flags}" run cargo test --workspace --all-features --doc "$@"

}
cmd_clean_doc () {

    cd_root
    local p="${ROOT_DIR}/target/doc"

    [[ -d "${p}" ]] || return 0
    rm -rf -- "${p}" || die "Failed to remove: ${p}" 2

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
    need_cmd cargo-deny

    run cargo deny check "$@"

}
cmd_test () {

    cd_root
    need_cmd cargo

    local package=""
    local doc=0
    local all=0
    local -a pass=()

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -p|--package)
                shift || true
                package="${1:-}"
                [[ -n "${package}" ]] || die "Error: -p/--package requires a value" 2
                [[ "${package}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "Error: invalid package name: ${package}" 2
                shift || true
            ;;
            -d|--doc)
                doc=1
                shift || true
            ;;
            -a|--all)
                all=1
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

    (( all )) && doc=0

    if has_cmd cargo-nextest; then

        if (( all )); then

            if [[ -n "${package}" ]]; then
                run cargo nextest run -p "${package}" --all-features "${pass[@]}"
                run cargo test -p "${package}" --all-features --doc "${pass[@]}"
                return 0
            fi

            run cargo nextest run --workspace --all-features "${pass[@]}"
            run cargo test --workspace --all-features --doc "${pass[@]}"
            return 0

        fi
        if (( doc )); then

            if [[ -n "${package}" ]]; then
                run cargo test -p "${package}" --all-features --doc "${pass[@]}"
                return 0
            fi

            run cargo test --workspace --all-features --doc "${pass[@]}"
            return 0

        fi
        if [[ -n "${package}" ]]; then
            run cargo nextest run -p "${package}" --all-features "${pass[@]}"
            return 0
        fi

        run cargo nextest run --workspace --all-features "${pass[@]}"
        return 0

    fi
    if (( all )); then

        if [[ -n "${package}" ]]; then
            run cargo test -p "${package}" --all-features "${pass[@]}"
            run cargo test -p "${package}" --all-features --doc "${pass[@]}"
            return 0
        fi

        run cargo test --workspace --all-features "${pass[@]}"
        run cargo test --workspace --all-features --doc "${pass[@]}"
        return 0

    fi
    if (( doc )); then

        if [[ -n "${package}" ]]; then
            run cargo test -p "${package}" --all-features --doc "${pass[@]}"
            return 0
        fi

        run cargo test --workspace --all-features --doc "${pass[@]}"
        return 0

    fi
    if [[ -n "${package}" ]]; then
        run cargo test -p "${package}" --all-features "${pass[@]}"
        return 0
    fi

    run cargo test --workspace --all-features "${pass[@]}"

}
cmd_hack () {

    cd_root
    need_cmd cargo
    has_cmd cargo-hack || die "cargo-hack not found. Run: vx ensure" 2

    local mode="powerset"
    local depth="2"
    local package=""
    local -a pass=()

    while [[ $# -gt 0 ]]; do
        case "${1}" in
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
            -p|--package)
                shift || true
                package="${1:-}"
                [[ -n "${package}" ]] || die "Error: -p/--package requires a value" 2
                [[ "${package}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "Error: invalid package name: ${package}" 2
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

    local -a base=( cargo hack check --workspace --keep-going )
    [[ -n "${package}" ]] && base=( cargo hack check -p "${package}" --keep-going )

    if [[ "${mode}" == "each" ]]; then
        run "${base[@]}" --each-feature "${pass[@]}"
        return 0
    fi

    run "${base[@]}" --feature-powerset --depth "${depth}" "${pass[@]}"

}
cmd_bench () {

    cd_root
    need_cmd cargo

    local package=""
    local -a pass=()

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -p|--package)
                shift || true
                package="${1:-}"
                [[ -n "${package}" ]] || die "Error: -p/--package requires a value" 2
                [[ "${package}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "Error: invalid package name: ${package}" 2
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

    if [[ -n "${package}" ]]; then
        run cargo bench -p "${package}" --all-features "${pass[@]}"
        return 0
    fi

    run cargo bench --workspace --all-features "${pass[@]}"

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
                [[ "${package}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "Error: invalid package name: ${package}" 2
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
cmd_clean_cache () {

    cd_root
    need_cmd cargo
    need_cmd cargo-ci-cache-clean
    run cargo-ci-cache-clean

}
cmd_msrv () {

    cd_root
    need_cmd cargo
    need_cmd rustc
    need_cmd jq
    need_cmd sort
    need_cmd tail
    need_cmd awk
    need_cmd sed

    local tc="" want="" have=""

    if [[ -n "${RUST_MSRV:-}" ]]; then

        tc="${RUST_MSRV#v}"
        [[ "${tc}" =~ ^[0-9]+\.[0-9]+$ ]] && tc="${tc}.0"
        [[ "${tc}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Error: invalid RUST_MSRV: ${RUST_MSRV}" 2

        echo "${tc}"
        return 0

    fi

    want="$(cargo metadata --no-deps --format-version 1 2>/dev/null | jq -r '.packages[].rust_version // empty' | sort -V | tail -n 1)"
    have="$(rustc -V | awk '{print $2}' | sed 's/[^0-9.].*$//')"
    tc="${want#v}"

    [[ -n "${want}" ]] || { echo "${have}"; return 0; }
    [[ "${tc}" =~ ^[0-9]+\.[0-9]+$ ]] && tc="${tc}.0"
    [[ "$(printf '%s\n%s\n' "${tc}" "${have}" | sort -V | awk 'NR==1{print;exit}')" == "${tc}" ]] || die "Rust too old: need >= ${tc}, have ${have}" 2

    echo "${tc}"

}
cmd_msrv_check () {

    local tc="$(cmd_msrv 2>/dev/null || true)"
    tc="${tc#v}"

    [[ "${tc}" =~ ^[0-9]+\.[0-9]+$ ]] && tc="${tc}.0"
    [[ "${tc}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid msrv value: ${tc}" 2

    rustup toolchain list 2>/dev/null | awk '{print $1}' | grep -Fxq "${tc}" || run rustup toolchain install "${tc}" --profile minimal
    run env RUSTFLAGS="" cargo +"${tc}" check --workspace --all-targets --all-features

}
cmd_msrv_test () {

    local tc="$(cmd_msrv 2>/dev/null || true)"
    tc="${tc#v}"

    [[ "${tc}" =~ ^[0-9]+\.[0-9]+$ ]] && tc="${tc}.0"
    [[ "${tc}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid msrv value: ${tc}" 2

    rustup toolchain list 2>/dev/null | awk '{print $1}' | grep -Fxq "${tc}" || run rustup toolchain install "${tc}" --profile minimal
    run env RUSTFLAGS="" cargo +"${tc}" test --workspace --all-targets --all-features --no-run

}
cmd_semver () {

    cd_root
    need_cmd git
    need_cmd cargo
    need_cmd cargo-semver-checks

    local remote="${VX_GIT_REMOTE:-origin}"
    local baseline="${CARGO_SEMVER_CHECKS_BASELINE_REV:-${VX_SEMVER_BASELINE:-}}"

    if [[ "${1:-}" == "--baseline" ]]; then
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

    if cargo semver-checks -h 2>/dev/null | grep -q -- '--baseline-rev'; then
        extra+=(--baseline-rev "${baseline}")
    fi

    run cargo semver-checks "${extra[@]}" "$@"

}
cmd_coverage () {

    cd_root
    need_cmd cargo
    need_cmd jq

    local upload=0
    local codecov_flags=""
    local codecov_name=""
    local codecov_version=""
    local codecov_token=""
    local mode="lcov"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --upload)
                upload=1
                shift
            ;;
            --mode)
                mode="${2-}"
                shift 2 || true
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

    if ! run cargo llvm-cov --version >/dev/null 2>&1; then
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

    if (( upload )); then
        local job_name="${codecov_name:-coverage-${GITHUB_RUN_ID:-local}}"
        codecov_upload "${out}" "${codecov_flags}" "${job_name}" "${codecov_version}" "${codecov_token}"
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

    if ! run cargo spellcheck --version >/dev/null 2>&1; then
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
    has_cmd cargo-deny || die "Error: cargo-deny not found. Install: cargo install cargo-deny" 2
    run cargo deny check advisories bans licenses sources "$@"

}
cmd_fix_audit () {

    cd_root
    need_cmd cargo
    has_cmd cargo-audit || die "Error: cargo-audit not found. Install: cargo install cargo-audit --features=fix" 2
    run cargo audit fix "$@"

}
cmd_doctor () {

    cd_root
    log "== Doctor =="

    log ""
    log "== Environment =="
    log "PWD: $(pwd)"
    log "Shell: ${SHELL:-unknown}"
    log "User: ${USER:-${USERNAME:-unknown}}"
    log "CI: ${CI:-0}  GITHUB_ACTIONS: ${GITHUB_ACTIONS:-0}"
    log "PATH: ${PATH}"

    log ""
    log "== OS / Kernel =="
    if has_cmd uname; then
        uname -a || true
        uname -s || true
        uname -m || true
    fi
    if [[ -f /etc/os-release ]]; then
        log "--- /etc/os-release ---"
        sed -n '1,20p' /etc/os-release 2>/dev/null || true
    fi
    if has_cmd sw_vers; then
        sw_vers || true
    fi

    log ""
    log "== Disk / CPU / Memory =="
    if has_cmd df; then
        df -h . 2>/dev/null || true
    fi
    if has_cmd nproc; then
        log "CPU cores: $(nproc 2>/dev/null || echo '?')"
    elif has_cmd sysctl; then
        sysctl -n hw.ncpu 2>/dev/null || true
    fi
    if has_cmd free; then
        free -h 2>/dev/null || true
    elif has_cmd vm_stat; then
        vm_stat 2>/dev/null | sed -n '1,12p' || true
    fi

    log ""
    log "== Git =="
    if has_cmd git; then
        git --version || true
        git rev-parse --is-inside-work-tree >/dev/null 2>&1 && {
            log "Repo: yes"
            git status -sb 2>/dev/null | sed -n '1,10p' || true
            git rev-parse --short HEAD 2>/dev/null || true
        } || log "Repo: no"
    else
        log "git: missing"
    fi

    log ""
    log "== Rust =="
    if has_cmd rustup; then
        rustup --version || true
        rustup show active-toolchain 2>/dev/null || true

        log "--- toolchains ---"
        rustup toolchain list 2>/dev/null || true

        log "--- components (installed) ---"
        rustup component list --installed 2>/dev/null || true
    else
        log "rustup: missing"
    fi

    if has_cmd rustc; then
        rustc -Vv || true
    else
        log "rustc: missing"
    fi

    if has_cmd cargo; then
        cargo -V || true
    else
        log "cargo: missing"
    fi

    if has_cmd cargo && has_cmd jq; then
        log ""
        log "== Cargo Workspace =="
        local msrv=""
        msrv="$(cmd_msrv 2>/dev/null || true)"
        [[ -n "${msrv}" ]] && log "MSRV: ${msrv}"

        local pkgs=""
        pkgs="$(cargo metadata --no-deps --format-version 1 2>/dev/null | jq -r '.packages | length' 2>/dev/null || true)"
        [[ -n "${pkgs}" ]] && log "Workspace packages: ${pkgs}"

        local members=""
        members="$(cargo metadata --no-deps --format-version 1 2>/dev/null | jq -r '.workspace_members | length' 2>/dev/null || true)"
        [[ -n "${members}" ]] && log "Workspace members: ${members}"
    else
        log ""
        log "== Cargo Workspace =="
        log "skip: cargo/jq not available for metadata"
    fi

    log ""
    log "== OS Tools (used by vx/CI) =="
    has_cmd curl     && curl --version 2>/dev/null | sed -n '1,2p' || log "curl: missing"
    has_cmd jq       && jq --version 2>/dev/null || log "jq: missing"
    has_cmd perl     && perl -v 2>/dev/null | sed -n '1,2p' || log "perl: missing"
    has_cmd awk      && awk --version 2>/dev/null | sed -n '1,2p' || log "awk: missing"
    has_cmd grep     && grep --version 2>/dev/null | sed -n '1,2p' || log "grep: missing"
    has_cmd sort     && sort --version 2>/dev/null | sed -n '1,2p' || log "sort: missing"
    has_cmd tail     && tail --version 2>/dev/null | sed -n '1,2p' || log "tail: missing"
    has_cmd hunspell && hunspell -v 2>/dev/null || log "hunspell: missing (spellcheck needs it)"
    has_cmd git      || true

    log ""
    log "== Cargo Tools (vx ensure installs) =="

    if has_cmd cargo-deny; then
        cargo deny --version 2>/dev/null || true
    else
        log "cargo-deny: missing"
    fi

    if has_cmd cargo-audit; then
        cargo audit --version 2>/dev/null || cargo audit -V 2>/dev/null || true
    else
        log "cargo-audit: missing"
    fi

    if has_cmd cargo-nextest; then
        cargo nextest --version 2>/dev/null || true
    else
        log "cargo-nextest: missing"
    fi

    if has_cmd cargo-hack; then
        cargo hack --version 2>/dev/null || true
    else
        log "cargo-hack: missing"
    fi

    if has_cmd cargo-llvm-cov; then
        cargo llvm-cov --version 2>/dev/null || true
    else
        log "cargo-llvm-cov: missing"
    fi

    if has_cmd cargo-spellcheck; then
        cargo spellcheck --version 2>/dev/null || true
    else
        log "cargo-spellcheck: missing"
    fi

    if has_cmd taplo; then
        taplo --version 2>/dev/null || true
    else
        log "taplo: missing"
    fi

    if has_cmd cargo-ci-cache-clean; then
        cargo-ci-cache-clean --version 2>/dev/null || true
    else
        log "cargo-ci-cache-clean: missing"
    fi

    log ""
    log "== Build Toolchain (nice-to-have) =="
    if has_cmd cc; then
        cc --version 2>/dev/null | sed -n '1,2p' || true
    elif has_cmd clang; then
        clang --version 2>/dev/null | sed -n '1,2p' || true
    elif has_cmd gcc; then
        gcc --version 2>/dev/null | sed -n '1,2p' || true
    else
        log "C compiler: missing (some crates may need it)"
    fi

    has_cmd pkg-config && pkg-config --version 2>/dev/null || log "pkg-config: missing (some native deps may need it)"
    has_cmd make       && make --version 2>/dev/null | sed -n '1,2p' || log "make: missing"

    log ""
    log "=================="
    log "OK"

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
cmd_get_version () {

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

    local name="${1:-}"
    [[ -n "${name}" ]] || die "Error: package name is required." 2

    only_publish_pkgs \
        | tr '[:upper:]' '[:lower:]' \
        | grep -Fxq -- "$(printf '%s' "${name}" | tr '[:upper:]' '[:lower:]')" \
        && { echo "yes"; return 0; }

    echo "no"

}
cmd_is_published () {

    cd_root
    need_cmd curl
    need_cmd grep

    local name="${1:-}"
    [[ -n "${name}" ]] || die "Error: crate name is required." 2
    [[ "$(cmd_is_publishable "${name}")" == "yes" ]] || die "Error: package ${name} is not publishable." 2

    local version=""
    version="$(cmd_get_version "${name}")"

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

    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        pkgs+=( "${line}" )
    done < <(only_publish_pkgs)

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
            run cargo publish --package "${p}" "${cargo_args[@]}" "$@"
        done

    else

        [[ "$(cmd_can_publish)" == "yes" ]] || die "Error: there is one/many packages already published" 2
        run cargo publish --workspace "${cargo_args[@]}" "$@"

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

    local action="yank"
    (( undo )) && action="undo yank"

    if ! is_ci; then
        confirm "About to ${action} ${package} v${version}. Continue?" || die "Aborted." 1
    fi

    local old_token="" old_token_set=0 xtrace=0
    [[ -n CARGO_REGISTRY_TOKEN ]] && { old_token_set=1; old_token="${CARGO_REGISTRY_TOKEN}"; }

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
        run cargo yank -p "${package}" --version "${version}" --undo "${pass[@]}"
        return 0
    fi

    run cargo yank -p "${package}" --version "${version}" "${pass[@]}"

}

cmd_ensure () {

    local rust=0 node=0

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --rust) rust=1; shift ;;
            --node) node=1; shift ;;
            --) shift; break ;;
            *) break ;;
        esac
    done

    cd_root

    printf "\n💥 Ensure OS Tools ... \n\n"

    ensure_pkg --no-update "$@" jq perl grep curl clang llvm-dev libclang-dev hunspell awk tail sed sort head wc xargs find git

    (( rust )) && ensure_rust
    (( node )) && ensure_node

    (( ! rust )) && ! has_cmd cargo && ensure_rust
    (( ! node )) && ! has_cmd node && ensure_node

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
    ensure_crate cargo-ci-cache-clean  cargo-ci-cache-clean
    ensure_crate cargo-semver-checks   cargo-semver-checks

}
cmd_ci_fast () {

    cmd_ensure

    printf "\n💥 Checking ...\n\n"
    cmd_check

    printf "\n💥 Testing ...\n\n"
    cmd_test

    printf "\n💥 Clippy ...\n\n"
    cmd_clippy

    cmd_clean_cache
    printf "\n✅ CI FAST Succeeded.\n\n"

}
cmd_ci_fmt () {

    cmd_ensure

    printf "\n💥 Check Audit ...\n\n"
    cmd_check_audit

    printf "\n💥 Check Format ...\n\n"
    cmd_check_fmt

    printf "\n💥 Check Taplo ...\n\n"
    cmd_check_taplo

    printf "\n💥 Check Prettier ...\n\n"
    cmd_check_prettier

    printf "\n💥 Check Spellcheck ...\n\n"
    cmd_spellcheck

    cmd_clean_cache
    printf "\n✅ CI Format Succeeded.\n\n"

}
cmd_ci_doc () {

    cmd_ensure

    printf "\n💥 Check Doc ...\n\n"
    cmd_check_doc

    printf "\n💥 Test Doc ...\n\n"
    cmd_test_doc

    cmd_clean_cache
    printf "\n✅ CI Doc Succeeded.\n\n"

}
cmd_ci_msrv () {

    cmd_ensure

    printf "\n💥 Check Msrv ...\n\n"
    cmd_msrv_check

    printf "\n💥 Test Msrv ...\n\n"
    cmd_msrv_test

    cmd_clean_cache
    printf "\n✅ CI MSRV Succeeded.\n\n"

}
cmd_ci_hack () {

    cmd_ensure

    printf "\n💥 Hacking ...\n\n"
    cmd_hack "$@"

    cmd_clean_cache
    printf "\n✅ CI HACKING Succeeded.\n\n"

}
cmd_ci_semver () {

    cmd_ensure

    printf "\n💥 Semver ...\n\n"
    cmd_semver "$@"

    cmd_clean_cache
    printf "\n✅ CI SEMVER Succeeded.\n\n"

}
cmd_ci_coverage () {

    cmd_ensure

    printf "\n💥 Coverage ...\n\n"
    cmd_coverage "$@"

    cmd_clean_cache
    printf "\n✅ CI Coverage Succeeded.\n\n"

}
cmd_ci_publish () {

    cmd_ensure

    printf "\n💥 Publishing ...\n\n"
    # cmd_publish "$@"

    cmd_clean_cache
    printf "\n✅ CI Publish Succeeded.\n\n"

}
cmd_ci_local () {

    cmd_ensure --rust --node

    printf "\n💥 Checking ...\n\n"
    cmd_check

    printf "\n💥 Testing ...\n\n"
    cmd_test

    printf "\n💥 Clippy ...\n\n"
    cmd_clippy

    printf "\n💥 Check Audit ...\n\n"
    cmd_check_audit

    printf "\n💥 Check Format ...\n\n"
    cmd_check_fmt

    printf "\n💥 Check Taplo ...\n\n"
    cmd_check_taplo

    printf "\n💥 Check Prettier ...\n\n"
    cmd_check_prettier

    printf "\n💥 Check Spellcheck ...\n\n"
    cmd_spellcheck

    printf "\n💥 Check Doc ...\n\n"
    cmd_check_doc

    printf "\n💥 Test Doc ...\n\n"
    cmd_test_doc

    printf "\n💥 Check Msrv ...\n\n"
    cmd_msrv_check

    printf "\n💥 Test Msrv ...\n\n"
    cmd_msrv_test

    printf "\n💥 Hacking ...\n\n"
    cmd_hack

    printf "\n💥 Semver ...\n\n"
    cmd_semver

    printf "\n💥 Coverage ...\n\n"
    cmd_coverage

    printf "\n✅ CI Pipeline Succeeded.\n\n"

}
