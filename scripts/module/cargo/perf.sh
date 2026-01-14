#!/usr/bin/env bash

cmd_perf_help () {

    info_ln "Perf :\n"

    printf '    %s\n' \
        "bloat               Check bloat for (binary size)" \
        "coverage            Coverage via cargo llvm-cov (lcov/codecov)" \
        "" \
        "samply              CPU profiling via samply (Firefox Profiler UI) for one target" \
        "samply-load         Load saved samply profile (default: profiles/samply.json)" \
        "" \
        "flame               CPU flamegraph via cargo flamegraph (output: SVG)" \
        "flame-open          Open saved flamegraph SVG (default: profiles/flame.svg)" \
        ''

}

cmd_bloat () {

    source <(parse "$@" -- bin out="profiles/bloat.info")

    local -a args=()
    [[ -n "${bin}" ]] && args+=( --bin "${bin}" )

    if [[ -n "${out}" ]]; then

        [[ "${out}" == */* ]] && run mkdir -p -- "${out%/*}"
        [[ -f "${out}" ]] || die "bloat: invalid file: ${out}" 2

        run_cargo bloat "${args[@]}" "${kwargs[@]}" > "${out}"
        success "Analysed: out file -> ${out}"

        return 0

    fi

    run_cargo bloat "${args[@]}" "${kwargs[@]}"

}
cmd_coverage () {

    ensure llvm-tools-preview jq
    source <(parse "$@" -- mode=lcov name flags version token out upload:bool package:list)

    local -a pkgs=()

    if [[ ${#package[@]} -gt 0 ]]; then

        local -a ws_pkgs=()
        mapfile -t ws_pkgs < <(run_cargo metadata --no-deps --format-version 1 2>/dev/null | jq -r '.packages[].name')

        local -A ws_set=()
        local -A seen=()
        local x="" p=""

        for x in "${ws_pkgs[@]-}"; do
            ws_set["${x}"]=1;
        done

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

        out="${out:-profiles/codecov.json}"
        run_cargo llvm-cov "${pkgs[@]}" --all-targets --all-features --codecov --output-path "${out}" "${kwargs[@]}"

    else

        out="${out:-profiles/lcov.info}"
        run_cargo llvm-cov "${pkgs[@]}" --all-targets --all-features --lcov --output-path "${out}" "${kwargs[@]}"

    fi

    if (( upload )); then

        ensure curl chmod mv mkdir

        [[ -n "${flags}" ]] || flags="crates"
        [[ -n "${name}"  ]] || name="coverage-${GITHUB_RUN_ID:-local}"

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

            local url_a="https://cli.codecov.io/${dist}/${resolved}/codecov"
            local url_b="https://cli.codecov.io/${resolved}/${dist}/codecov"

            local sha_a="https://cli.codecov.io/${dist}/${resolved}/codecov.SHA256SUM"
            local sha_b="https://cli.codecov.io/${resolved}/${dist}/codecov.SHA256SUM"

            local sig_a="https://cli.codecov.io/${dist}/${resolved}/codecov.SHA256SUM.sig"
            local sig_b="https://cli.codecov.io/${resolved}/${dist}/codecov.SHA256SUM.sig"

            local tmp_dir="$(mktemp -d "${cache_dir}/codecov.tmp.XXXXXX" 2>/dev/null || true)"

            if [[ -z "${tmp_dir}" || ! -d "${tmp_dir}" ]]; then
                tmp_dir="${cache_dir}/codecov.tmp.$$"
                mkdir -p -- "${tmp_dir}" || die "Codecov: failed to create temp dir." 2
            fi

            trap 'rm -rf -- "${tmp_dir}" 2>/dev/null || true' RETURN

            local tmp_bin="${tmp_dir}/codecov"
            local tmp_sha="${tmp_dir}/codecov.SHA256SUM"
            local tmp_sig="${tmp_dir}/codecov.SHA256SUM.sig"

            rm -f -- "${tmp_bin}" "${tmp_sha}" "${tmp_sig}" 2>/dev/null || true

            if ! run curl -fsSL -o "${tmp_bin}" "${url_a}"; then
                run curl -fsSL -o "${tmp_bin}" "${url_b}"
            fi
            if ! run curl -fsSL -o "${tmp_sha}" "${sha_a}"; then
                run curl -fsSL -o "${tmp_sha}" "${sha_b}"
            fi
            if ! curl -fsSL -o "${tmp_sig}" "${sig_a}" 2>/dev/null; then
                curl -fsSL -o "${tmp_sig}" "${sig_b}" 2>/dev/null || rm -f -- "${tmp_sig}" 2>/dev/null || true
            fi
            if [[ -f "${tmp_sig}" ]] && has gpg; then

                local keyring="${tmp_dir}/trustedkeys.gpg"
                local keyfile="${tmp_dir}/codecov.pgp.asc"

                run curl -fsSL -o "${keyfile}" "https://keybase.io/codecovsecurity/pgp_keys.asc"
                gpg --no-default-keyring --keyring "${keyring}" --import "${keyfile}" >/dev/null 2>&1 || true
                gpg --no-default-keyring --keyring "${keyring}" --verify "${tmp_sig}" "${tmp_sha}" >/dev/null 2>&1 || die "Codecov: SHA256SUM signature verification failed." 2

            fi

            local got="" want="$(awk '$2 ~ /(^|\/)codecov$/ { print $1; exit }' "${tmp_sha}" 2>/dev/null || true)"

            [[ -n "${want}" ]] || die "Codecov: invalid SHA256SUM file." 2

            if has sha256sum; then got="$(sha256sum "${tmp_bin}" 2>/dev/null | awk '{print $1}' || true)"
            elif has shasum; then got="$(shasum -a 256 "${tmp_bin}" 2>/dev/null | awk '{print $1}' || true)"
            elif has openssl; then got="$(openssl dgst -sha256 "${tmp_bin}" 2>/dev/null | awk '{print $NF}' || true)"
            else die "Codecov: no SHA256 tool found (need sha256sum or shasum or openssl)." 2
            fi

            [[ -n "${got}" ]] || die "Codecov: failed to compute checksum." 2
            [[ "${got}" == "${want}" ]] || die "Codecov: checksum mismatch." 2

            run chmod +x "${tmp_bin}"
            run mv -f -- "${tmp_bin}" "${bin}"
            run "${bin}" --version >/dev/null 2>&1

        fi

        local -a args=( --verbose upload-process --disable-search --fail-on-error -t "${token}" -f "${out}" )

        [[ -n "${flags}" ]] && args+=( -F "${flags}" )
        [[ -n "${name}"  ]] && args+=( -n "${name}" )

        run "${bin}" "${args[@]}"
        success "Ok: Codecov file upload."

    fi

    success "OK Codecov processed -> ${out}"

}

cmd_samply () {

    ensure samply

    source <(parse "$@" -- \
        bin test bench example toolchain out="profiles/samply.json" nightly:bool stable:bool msrv:bool save_only:bool \
        rate address duration package:list \
    )

    [[ -z "${bin}"  || -z "${example}" ]] || die "samply: use only one of --bin or --example" 2
    [[ -z "${bench}" || -z "${test}"   ]] || die "samply: use only one of --bench or --test" 2
    [[ -z "${bench}${example}"         ]] || die "samply: use only one of --bench or --example" 2

    local -a args=( samply record )
    local -a cargo=( cargo )
    local -a pkgs=()
    local -A seen=()
    local p=""

    (( stable  )) && toolchain="stable"
    (( nightly )) && toolchain="nightly"
    (( msrv    )) && toolchain="msrv"

    if [[ "${toolchain}" == "stable" ]]; then cargo+=( +"$(stable_version)" )
    elif [[ "${toolchain}" == "nightly" ]]; then cargo+=( +"$(nightly_version)" )
    elif [[ "${toolchain}" == "msrv" ]]; then cargo+=( +"$(msrv_version)" )
    elif [[ -n "${toolchain}" ]]; then cargo+=( +"${toolchain}" )
    fi

    if [[ -n "${bench}" ]]; then cargo+=( bench --bench "${bench}" )
    elif [[ -n "${example}" ]]; then cargo+=( run --example "${example}" )
    elif [[ -n "${test}" ]]; then cargo+=( test --test "${test}" )
    else cargo+=( run ); [[ -n "${bin}" ]] && cargo+=( --bin "${bin}" )
    fi

    for p in "${package[@]-}"; do

        [[ -n "${p}" ]] || continue
        [[ -n "${seen[${p}]-}" ]] && continue

        seen["${p}"]=1
        pkgs+=( -p "${p}" )

    done

    (( ${#seen[@]} <= 1 )) || die "samply: --package supports at most one package" 2

    (( save_only )) && args+=( --save-only )

    [[ -n "${rate}"  ]] && args+=( --rate "${rate}" )
    [[ -n "${address}"  ]] && args+=( --address "${address}" )
    [[ -n "${duration}"  ]] && args+=( --duration "${duration}" )

    [[ -n "${out}"  ]] && args+=( -o "${out}" )
    [[ "${out}" == */* ]] && run mkdir -p -- "${out%/*}"

    RUSTFLAGS="${RUSTFLAGS:-} -C force-frame-pointers=yes -g" run "${args[@]}" -- "${cargo[@]}" "${pkgs[@]}" "${kwargs[@]}"

}
cmd_samply_load () {

    ensure samply
    source <(parse "$@" -- :file="profiles/samply.json")

    [[ -f "${file}" ]] || die "file not found: ${file}" 2
    run samply load "${file}"

}

cmd_flame () {

    ensure flamegraph
    source <(parse "$@" -- bin test bench example toolchain out="profiles/flamegraph.svg" nightly:bool stable:bool msrv:bool package:list)

    [[ -z "${bin}"  || -z "${example}" ]] || die "flame: use only one of --bin or --example" 2
    [[ -z "${bench}" || -z "${test}"   ]] || die "flame: use only one of --bench or --test" 2
    [[ -z "${bench}${example}"         ]] || die "flame: use only one of --bench or --example" 2

    local -a cargo=( cargo )
    local -a args=( flamegraph )
    local -a pkgs=()
    local -A seen=()
    local p=""

    (( stable  )) && toolchain="stable"
    (( nightly )) && toolchain="nightly"
    (( msrv    )) && toolchain="msrv"

    if [[ "${toolchain}" == "stable" ]]; then cargo+=( +"$(stable_version)" )
    elif [[ "${toolchain}" == "nightly" ]]; then cargo+=( +"$(nightly_version)" )
    elif [[ "${toolchain}" == "msrv" ]]; then cargo+=( +"$(msrv_version)" )
    elif [[ -n "${toolchain}" ]]; then cargo+=( +"${toolchain}" )
    fi

    if [[ -n "${bench}" ]]; then args+=( --bench "${bench}" )
    elif [[ -n "${example}" ]]; then args+=( --example "${example}" )
    elif [[ -n "${test}" ]]; then args+=( --test "${test}" )
    else [[ -n "${bin}" ]] && args+=( --bin "${bin}" )
    fi

    for p in "${package[@]-}"; do

        [[ -n "${p}" ]] || continue
        [[ -n "${seen[${p}]-}" ]] && continue

        seen["${p}"]=1
        pkgs+=( -p "${p}" )

    done

    (( ${#seen[@]} <= 1 )) || die "flame: --package supports at most one package" 2

    [[ -n "${out}"  ]] && args+=( -o "${out}" )
    [[ "${out}" == */* ]] && run mkdir -p -- "${out%/*}"

    RUSTFLAGS="${RUSTFLAGS:-} -C force-frame-pointers=yes -g" run "${cargo[@]}" "${args[@]}" "${pkgs[@]}" "${kwargs[@]}"

}
cmd_flame_open () {

    ensure flamegraph
    source <(parse "$@" -- :file="profiles/flamegraph.svg")

    [[ -f "${file}" ]] || die "file not found: ${file}" 2
    open_path "${file}"

}
