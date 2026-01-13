#!/usr/bin/env bash

cmd_deps_help () {

    info_ln "Deps :\n"

    printf '    %s\n' \
        "vet                 Check vet (cargo vet check)" \
        "vet-fmt             Format vet (cargo vet fmt)" \
        "vet-diff            Check diff cargo vet diff" \
        "vet-suggest         Suggest vet rules (cargo vet suggest)" \
        "vet-import          Import by vet (cargo vet import)" \
        "vet-allow           Trust crate (cargo vet trust)" \
        "vet-deny            Violation crate (vet record-violation)" \
        "vet-renew           Renew crate permission (cargo vet renew)" \
        '' \
        "hack                Hack workspace (cargo hack feature-matrix checks)" \
        "udeps               Check udeps (unused deps)" \
        "bloat               Check bloat for (binary size)" \
        "fuzz                Fuzzing workspace or -p/--packages (cargo fuzz targets)" \
        "sanitizer           Sanitizer for workspace or -p/--packages pipeline (asan/tsan/msan/lsan)" \
        "miri                Run miri checks" \
        "semver              Check semver for current crates version" \
        "coverage            Run cargo llvm-cov (lcov/codecov)" \
        ''

}

cmd_ensure_vet () {

    [[ -f "${ROOT_DIR}/Cargo.lock" ]] || run_cargo generate-lockfile
    [[ -d "${ROOT_DIR}/supply-chain" ]] || run_cargo vet init

}
cmd_vet_fmt () {

    cmd_ensure_vet
    run_cargo vet fmt "$@"

}
cmd_vet () {

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
