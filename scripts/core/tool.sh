#!/usr/bin/env bash

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || { printf '%s\n' "tool.sh: this file should not be run externally." >&2; exit 2; }
[[ -n "${TOOL_LOADED:-}" ]] && return 0
TOOL_LOADED=1

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/pkg.sh"

tool_path_prepend () {

    local d="${1-}"
    [[ -n "${d}" ]] || return 0

    case ":${PATH-}:" in
        *":${d}:"*) ;;
        *) PATH="${d}:${PATH-}" ;;
    esac

    export PATH
    return 0

}
tool_export_cargo_bin () {

    tool_path_prepend "${HOME}/.cargo/bin"

    if [[ -n "${GITHUB_PATH:-}" ]]; then
        printf '%s\n' "${HOME}/.cargo/bin" >> "${GITHUB_PATH}"
    fi

    return 0

}
pick_sort_locale () {

    local line=""

    if has locale; then

        while IFS= read -r line; do

            case "${line}" in
                C.UTF-8)     printf '%s\n' "C.UTF-8"; return 0 ;;
                en_US.UTF-8) printf '%s\n' "en_US.UTF-8"; return 0 ;;
            esac

        done < <( locale -a 2>/dev/null || true )

    fi

    printf '%s\n' "C"

}
pick_sort_bin () {

    ensure_pkg sort

    LC_ALL=C sort -V </dev/null >/dev/null 2>&1 && { printf '%s\n' "sort"; return 0; }

    die "Need GNU sort with -V. (mac) ensure_pkg sort should have shimmed it; check pkg_mac_gnu_shim/verify." 2

}
sort_ver () {

    local loc="" sbin=""

    loc="$(pick_sort_locale)"
    sbin="$(pick_sort_bin)"

    LC_ALL="${loc}" "${sbin}" -V

}
normalize_version () {

    local tc="${1:-}"
    tc="${tc#v}"

    case "${tc}" in
        stable|beta|nightly) printf '%s\n' "${tc}"; return 0 ;;
        nightly-????-??-??)  printf '%s\n' "${tc}"; return 0 ;;
    esac

    [[ "${tc}" =~ ^[0-9]+\.[0-9]+$ ]] && tc="${tc}.0"
    [[ "${tc}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Error: invalid version: ${1}" 2

    printf '%s\n' "${tc}"

}
rust_msrv_version () {

    ensure_pkg jq awk sed tail sort

    local tc="" want="" have=""

    if [[ -n "${RUST_MSRV:-}" ]]; then

        tc="$(normalize_version "${RUST_MSRV}")"
        [[ "${tc}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Error: invalid RUST_MSRV (need x.y.z): ${RUST_MSRV}" 2

        printf '%s\n' "${tc}"
        return 0

    fi

    have="$(rustc -V 2>/dev/null | awk '{print $2}' | sed 's/[^0-9.].*$//')"
    [[ -n "${have}" ]] || die "Error: rustc not available to detect current version" 2

    if has cargo; then

        want="$(
            cargo metadata --no-deps --format-version 1 2>/dev/null \
                | jq -r '.packages[].rust_version // empty' \
                | sort_ver \
                | tail -n 1
        )"

    fi

    [[ -n "${want}" ]] || { printf '%s\n' "${have}"; return 0; }

    tc="$(normalize_version "${want}")"
    [[ "${tc}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Error: invalid workspace rust_version (need x.y.z): ${want}" 2

    [[ "$(printf '%s\n%s\n' "${tc}" "${have}" | sort_ver | awk 'NR==1{print;exit}')" == "${tc}" ]] \
        || die "Rust too old: need >= ${tc}, have ${have}" 2

    printf '%s\n' "${tc}"

}
ensure_toolchain () {

    local tc="${1:-}"
    [[ -n "${tc}" ]] || die "Error: ensure_toolchain needs a toolchain" 2

    rustup run "${tc}" rustc -V >/dev/null 2>&1 && return 0

    run rustup toolchain install "${tc}" --profile minimal
    rustup run "${tc}" rustc -V >/dev/null 2>&1 || die "rustc not working after install: ${tc}" 2

}
ensure_rust () {

    ensure_pkg curl
    local stable="" nightly="" msrv="" uname_s=""

    stable="$(normalize_version "${RUST_STABLE:-stable}")"
    nightly="$(normalize_version "${RUST_NIGHTLY:-nightly}")"
    uname_s="$(uname -s 2>/dev/null || true)"

    tool_export_cargo_bin

    if ! has rustup; then

        case "${uname_s}" in
            MSYS*|MINGW*|CYGWIN*)
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

        tool_export_cargo_bin
        [[ -f "${HOME}/.cargo/env" ]] && source "${HOME}/.cargo/env" || true

        has rustup || die "rustup installed but not found in PATH (check ~/.cargo/bin)." 2

    fi

    msrv="$( ( rust_msrv_version ) 2>/dev/null || true )"
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

    has rustup || ensure_rust

    if [[ -z "${tc}" ]]; then
        tc="$(normalize_version "${RUST_STABLE:-stable}")"
    fi

    ensure_toolchain "${tc}"

    if [[ "${comp}" == "llvm-tools-preview" ]]; then

        rustup component list --toolchain "${tc}" --installed 2>/dev/null | grep -qE '^(llvm-tools|llvm-tools-preview)\b' && return 0

        run rustup component add --toolchain "${tc}" llvm-tools-preview 2>/dev/null || run rustup component add --toolchain "${tc}" llvm-tools
        return 0

    fi

    rustup component list --toolchain "${tc}" --installed 2>/dev/null | grep -qE "^${comp}\\b" && return 0
    run rustup component add --toolchain "${tc}" "${comp}"

}
ensure_crate () {

    local crate="${1:-}"
    local bin="${2:-}"

    [[ -n "${crate}" ]] || die "Error: ensure_crate requires <crate>" 2
    [[ -n "${bin}" ]]   || die "Error: ensure_crate requires <bin>" 2
    shift 2 || true

    has cargo || ensure_rust
    tool_export_cargo_bin

    has "${bin}" && return 0

    run cargo install --locked "${crate}" "$@" || die "Failed to install: ${crate}" 2
    has "${bin}" || die "Installed ${crate} but '${bin}' not found in PATH (check ~/.cargo/bin)." 2

}
ensure_node () {

    local want="${1:-25}"

    local v="" major=""

    if has node; then

        v="$(node --version 2>/dev/null || true)"
        v="${v#v}"
        major="${v%%.*}"

        [[ "${major}" =~ ^[0-9]+$ ]] || die "Can't parse Node.js version: ${v}" 2

        if (( major >= want )) && has npx && npx --version >/dev/null 2>&1; then
            return 0
        fi

    fi

    case "$(os_name)" in
        windows)
            ensure_pkg nodejs npm
        ;;
        *)
            ensure_pkg curl

            export VOLTA_HOME="${VOLTA_HOME:-${HOME}/.volta}"
            tool_path_prepend "${VOLTA_HOME}/bin"

            if ! has volta; then
                run curl -fsSL https://get.volta.sh | bash || die "Failed to install Volta." 2
            fi

            tool_path_prepend "${VOLTA_HOME}/bin"
            has volta || die "Volta installed but not found in PATH. Restart shell or fix PATH/VOLTA_HOME." 2

            run volta install "node@${want}" || die "Failed to install Node via Volta." 2
        ;;
    esac

    pkg_hash_clear

    has node || die "Node install finished but 'node' not found in PATH." 2
    has npx  || die "npx not found after Node install." 2
    npx --version >/dev/null 2>&1 || die "npx exists but failed to run. Check environment/PATH." 2

    v="$(node --version 2>/dev/null || true)"
    v="${v#v}"
    major="${v%%.*}"

    [[ "${major}" =~ ^[0-9]+$ ]] || die "Can't parse Node.js version after install: ${v}" 2
    (( major >= want )) || die "Node install did not satisfy requirement (need ${want}+, found v${v})." 2

    if [[ -n "${GITHUB_PATH:-}" ]]; then
        printf '%s\n' "${VOLTA_HOME:-${HOME}/.volta}/bin" >> "${GITHUB_PATH}"
    fi

}
ensure_python () {

    local os=""
    os="$(os_name)"

    case "${os}" in
        windows) ensure_pkg python pip ;;
        *)       ensure_pkg python3 pip ;;
    esac

    pkg_hash_clear

    local py=""
    if has python3; then
        py="python3"
    elif has python; then
        py="python"
    else
        die "ensure_python: python not found after install" 2
    fi

    run "${py}" -c 'import sys; sys.exit(0)' >/dev/null 2>&1 || die "ensure_python: python exists but failed to run" 2

    if ! run "${py}" -m pip --version >/dev/null 2>&1; then
        run "${py}" -m ensurepip --upgrade >/dev/null 2>&1 || true
    fi

    run "${py}" -m pip --version >/dev/null 2>&1 || die "ensure_python: pip not available" 2

    if (( QUIET_ENV )); then
        run "${py}" -m pip install --user --upgrade pip setuptools wheel --disable-pip-version-check >/dev/null 2>&1 \
            || die "ensure_python: pip upgrade failed" 2
    else
        run "${py}" -m pip install --user --upgrade pip setuptools wheel --disable-pip-version-check \
            || die "ensure_python: pip upgrade failed" 2
    fi

    run "${py}" -m pip --version >/dev/null 2>&1 || die "ensure_python: pip exists but failed to run" 2

}
ensure () {

    local yes=0 quiet=0 verbose=0
    local -a wants=()

    source <(parse "$@" -- --yes:bool --quiet:bool --verbose:bool :wants:list)

    local eff_yes=0 eff_quiet=0 eff_verbose=0
    (( YES_ENV || yes )) && eff_yes=1
    (( QUIET_ENV || quiet )) && eff_quiet=1
    (( VERBOSE_ENV || verbose )) && eff_verbose=1

    (( ${#wants[@]} )) || return 0
    local want=""

    for want in "${wants[@]}"; do

        [[ -n "${want}" ]] || continue
        has "${want}" && { print "$("$want" --version)"; continue; }

        case "${want}" in
            python|python3|python3.*|pip|pip3)
                YES_ENV="${eff_yes}" QUIET_ENV="${eff_quiet}" VERBOSE_ENV="${eff_verbose}" ensure_python
            ;;
            node|nodejs)
                YES_ENV="${eff_yes}" QUIET_ENV="${eff_quiet}" VERBOSE_ENV="${eff_verbose}" ensure_node
                has node || die "ensure: missing 'node' after install" 2
            ;;
            rust|rustc|rustup|cargo)
                YES_ENV="${eff_yes}" QUIET_ENV="${eff_quiet}" VERBOSE_ENV="${eff_verbose}" ensure_rust
                has "${want}" || die "ensure: missing '${want}' after install" 2
            ;;
            rustfmt|clippy|llvm-tools-preview)
                YES_ENV="${eff_yes}" QUIET_ENV="${eff_quiet}" VERBOSE_ENV="${eff_verbose}" ensure_rust
                YES_ENV="${eff_yes}" QUIET_ENV="${eff_quiet}" VERBOSE_ENV="${eff_verbose}" ensure_component "${want}"
            ;;
            taplo)
                YES_ENV="${eff_yes}" QUIET_ENV="${eff_quiet}" VERBOSE_ENV="${eff_verbose}" ensure_crate taplo-cli taplo
            ;;
            cargo-audit)
                YES_ENV="${eff_yes}" QUIET_ENV="${eff_quiet}" VERBOSE_ENV="${eff_verbose}" ensure_crate cargo-audit cargo-audit --features fix
            ;;
            cargo-*)
                YES_ENV="${eff_yes}" QUIET_ENV="${eff_quiet}" VERBOSE_ENV="${eff_verbose}" ensure_crate "${want}" "${want}"
            ;;
            *)
                YES_ENV="${eff_yes}" QUIET_ENV="${eff_quiet}" VERBOSE_ENV="${eff_verbose}" ensure_pkg "${want}"
            ;;
        esac

    done

    return 0

}
