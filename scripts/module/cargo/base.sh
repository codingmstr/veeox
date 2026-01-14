#!/usr/bin/env bash

active_version () {

    tool_active_version

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
resolve_cmd () {

    source <(parse "$@" -- :name:str)

    case "${name}" in
        taplo-cli) name="taplo" ;;
        fd|fd-find) name="fdfind" ;;
        ripgrep) name="rg" ;;
        rust) name="rustc" ;;
        bat) name="batcat" ;;
        ci-cache-clean|semver-checks ) name="cargo-${name}" ;;
    esac

    local n="${name}" n1="${name//_/-}" n2="${name//-/_}"

    command -v -- "${n}"  >/dev/null 2>&1 && { printf '%s\n' "${n}"; return 0; }
    command -v -- "${n1}" >/dev/null 2>&1 && { printf '%s\n' "${n1}"; return 0; }
    command -v -- "${n2}" >/dev/null 2>&1 && { printf '%s\n' "${n2}"; return 0; }

    if [[ "${n}" != cargo-* ]]; then

        [[ "${n}" == "miri" ]] && command -v -- cargo-miri >/dev/null 2>&1 && { printf '%s\n' "cargo +nightly miri"; return 0; }

        command -v -- "cargo-${n}"  >/dev/null 2>&1 && { printf '%s\n' "cargo ${n}";  return 0; }
        command -v -- "cargo-${n1}" >/dev/null 2>&1 && { printf '%s\n' "cargo ${n1}"; return 0; }
        command -v -- "cargo-${n2}" >/dev/null 2>&1 && { printf '%s\n' "cargo ${n2}"; return 0; }

    else

        command -v -- "${n}"  >/dev/null 2>&1 && { printf '%s\n' "${n}"; return 0; }
        command -v -- "${n1}" >/dev/null 2>&1 && { printf '%s\n' "${n1}"; return 0; }
        command -v -- "${n2}" >/dev/null 2>&1 && { printf '%s\n' "${n2}"; return 0; }

    fi

    return 1

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
        add|rm|bench|build|check|test|clean|doc|fetch|fix|generate-lockfile|help|init|install|locate-project|login|logout|metadata|new|info) : ;;
        owner|package|pkgid|publish|remove|report|run|rustc|rustdoc|search|tree|uninstall|update|upgrade|vendor|verify-project|version|yank) : ;;
        clippy|fmt|miri|samply|flamegraph) ensure "${sub}" ;;
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
    if [[ "${command}" == "nextest" || "${command}" == "hack" ]]; then
        if [[ "${1-}" != "" && "${1}" != "--" && "${1}" != -* ]]; then
            nested="${1}"
            shift || true
        fi
    fi

    for a in "$@"; do

        [[ "${a}" == "--" ]] && break

        case "${a}" in
            -p|--package|--package=*|--manifest-path|--manifest-path=*|--workspace|--workspace=*|--all)
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

    if [[ -n "${nested}" ]]; then
        run_cargo "${command}" "${nested}" --workspace "${extra[@]}" "$@"
    else
        run_cargo "${command}" --workspace "${extra[@]}" "$@"
    fi

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
