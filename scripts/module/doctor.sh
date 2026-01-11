#!/usr/bin/env bash

doctor_usage () {

    printf '    %s\n' \
        "doctor              Summery of (system + tools + git) full diagnostics" \
        ''

}
doctor_pick_ver_line () {

    local s="${1-}"
    local line=""

    while IFS= read -r line; do

        line="${line//$'\r'/}"
        line="${line#"${line%%[!$' \t']*}"}"
        line="${line%"${line##*[!$' \t']}"}"

        [[ -n "${line}" ]] || continue
        [[ "${line}" =~ [0-9]+\.[0-9]+ ]] && { printf '%s' "${line}"; return 0; }

    done <<< "${s}"

    while IFS= read -r line; do

        line="${line//$'\r'/}"
        line="${line#"${line%%[!$' \t']*}"}"
        line="${line%"${line##*[!$' \t']}"}"

        [[ -n "${line}" ]] || continue
        printf '%s' "${line}"
        return 0

    done <<< "${s}"

    printf '%s' ""
    return 0

}
doctor_ver () {

    ensure head tr

    local out=""

    out="$( { "$@" --version 2>&1 || true; } | head -n 6 | tr -d '\r' )"
    out="$(doctor_pick_ver_line "${out}")"
    [[ -n "${out}" ]] && { printf '%s' "${out}"; return 0; }

    out="$( { "$@" -V 2>&1 || true; } | head -n 6 | tr -d '\r' )"
    out="$(doctor_pick_ver_line "${out}")"
    [[ -n "${out}" ]] && { printf '%s' "${out}"; return 0; }

    out="$( { "$@" version 2>&1 || true; } | head -n 6 | tr -d '\r' )"
    out="$(doctor_pick_ver_line "${out}")"
    [[ -n "${out}" ]] && { printf '%s' "${out}"; return 0; }

    printf '%s' ""
    return 0

}
doctor_status () {

    local kind="${1:-ok}"
    local name="${2:-}"
    local msg="${3:-}"

    case "${kind}" in
        ok)
            printf '  ✅ %-18s %s\n' "${name}" "${msg}"
            ok=$(( ok + 1 ))
        ;;
        warn)
            printf '  ⚠️ %-18s %s\n' "${name}" "${msg}"
            warn=$(( warn + 1 ))
        ;;
        fail)
            printf '  ❌ %-18s %s\n' "${name}" "${msg}"
            fail=$(( fail + 1 ))
        ;;
        *)
            printf '  ✅ %-18s %s\n' "${name}" "${msg}"
            ok=$(( ok + 1 ))
        ;;
    esac

}
doctor_tool () {

    local missing_kind="${1:-warn}"
    local name="${2:-}"
    local cmd="${3:-}"

    shift 3 || true

    if ! has "${cmd}"; then
        doctor_status "${missing_kind}" "${name}" "missing"
        return 0
    fi

    local v="$(doctor_ver "${cmd}" "$@")"

    if [[ -z "${v}" ]]; then
        doctor_status warn "${name}" "unknown"
        return 0
    fi
    if [[ "${v}" == *"error:"* || "${v}" == *"fatal error:"* ]]; then
        doctor_status warn "${name}" "${v}"
        return 0
    fi

    doctor_status ok "${name}" "${v}"
    return 0

}
doctor_cargo_sub () {

    local label="${1:-}"
    local sub="${2:-}"
    local bin="${3:-}"

    if ! has cargo; then
        doctor_status fail "cargo" "missing"
        return 0
    fi
    if ! has "${bin}"; then
        doctor_status warn "${label}" "missing"
        return 0
    fi

    local v="$(doctor_ver cargo "${sub}")"

    [[ -n "${v}" ]] || { doctor_status warn "${label}" "unknown"; return 0; }

    if [[ "${v}" == *"error:"* || "${v}" == *"fatal error:"* ]]; then
        doctor_status warn "${label}" "${v}"
        return 0
    fi

    doctor_status ok "${label}" "${v}"
    return 0

}
doctor_has_component () {

    ensure awk grep

    local tc="${1:-}"
    local comp_re="${2:-}"

    rustup component list --toolchain "${tc}" --installed 2>/dev/null | awk '{print $1}' | grep -qE "${comp_re}"

}
doctor_toolchain_installed () {

    ensure awk

    local tc="${1:-}"
    [[ -n "${tc}" ]] || return 1

    rustup toolchain list 2>/dev/null \
        | awk '{print $1}' \
        | awk -v tc="${tc}" '
            $0 == tc { found=1 }
            index($0, tc "-") == 1 { found=1 }
            END { exit(found ? 0 : 1) }
        '

}
doctor_toolchain () {

    local name="${1:-}"
    local tc="${2:-}"

    [[ -n "${tc}" ]] || { doctor_status warn "${name}" "unknown"; return 0; }

    if doctor_toolchain_installed "${tc}"; then
        doctor_status ok "${name}" "${tc}"
        return 0
    fi

    doctor_status warn "${name}" "missing (${tc})"
    return 0

}
doctor_sys () {

    ensure awk grep

    local distro="unknown" wsl="No" ci="No"
    local os="unknown" kernel="unknown" arch="unknown" shell="${SHELL:-unknown}"

    is_ci && ci="Yes"

    os="$(uname -s 2>/dev/null || printf '%s' unknown)"
    kernel="$(uname -r 2>/dev/null || printf '%s' unknown)"
    arch="$(uname -m 2>/dev/null || printf '%s' unknown)"

    if [[ -r /etc/os-release ]]; then
        distro="$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-unknown}")"
    elif [[ "${os}" == "Darwin" ]]; then
        distro="macOS"
    elif [[ "${os}" == MINGW* || "${os}" == MSYS* || "${os}" == CYGWIN* ]]; then
        distro="Windows (Git Bash)"
    fi

    if [[ -n "${WSL_INTEROP:-}" || -n "${WSL_DISTRO_NAME:-}" ]]; then
        wsl="Yes"
    elif [[ -r /proc/version ]] && grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        wsl="Yes"
    fi

    local cpu="" cores="unknown" mem="unknown" disk="unknown"

    if has lscpu; then
        cpu="$(lscpu 2>/dev/null | awk -F: '/Model name/ { sub(/^[ \t]+/,"",$2); print $2; exit }' || true)"
    fi
    if [[ -z "${cpu}" && -r /proc/cpuinfo ]]; then
        cpu="$(awk -F: '/model name/ { sub(/^[ \t]+/,"",$2); print $2; exit }' /proc/cpuinfo 2>/dev/null || true)"
    fi
    if [[ -z "${cpu}" && "${os}" == "Darwin" ]] && has sysctl; then
        cpu="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
    fi
    [[ -n "${cpu}" ]] || cpu="unknown"

    if has nproc; then
        cores="$(nproc 2>/dev/null || printf '%s' unknown)"
    elif has getconf; then
        cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '%s' unknown)"
    elif [[ "${os}" == "Darwin" ]] && has sysctl; then
        cores="$(sysctl -n hw.ncpu 2>/dev/null || printf '%s' unknown)"
    fi

    if has free; then
        mem="$(free -h 2>/dev/null | awk '/^Mem:/ { print $2 " total, " $7 " avail"; exit }' || true)"
    elif [[ "${os}" == "Darwin" ]] && has sysctl; then
        local mem_bytes="0"
        mem_bytes="$(sysctl -n hw.memsize 2>/dev/null || true)"
        [[ "${mem_bytes}" =~ ^[0-9]+$ ]] && mem="$(( mem_bytes / 1024 / 1024 ))Mi total"
    fi
    [[ -n "${mem}" ]] || mem="unknown"

    disk="$(LC_ALL=C df -hP . 2>/dev/null | awk 'NR==2 { print $4 " free of " $2 " (" $5 " used)"; exit }' || true)"
    [[ -n "${disk}" ]] || disk="unknown"

    info_ln '==> OS \n'

    doctor_status ok "OS" "${os}"
    doctor_status ok "Distro" "${distro}"
    doctor_status ok "Kernel" "${kernel}"
    doctor_status ok "Disk" "${disk}"
    doctor_status ok "CPU" "${cpu}"
    doctor_status ok "Memory" "${mem}"
    doctor_status ok "Shell" "${shell}"
    doctor_status ok "Cores" "${cores}"
    doctor_status ok "Arch" "${arch}"
    doctor_status ok "WSL" "${wsl}"
    doctor_status ok "CI" "${ci}"

}
doctor_github () {

    info_ln '==> Github \n'

    local root="$(pwd -P 2>/dev/null || pwd 2>/dev/null || printf '%s' '.')"

    if has git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then

        root="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "${root}")"

        local branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '%s' unknown)"
        local head="$(git rev-parse --short HEAD 2>/dev/null || printf '%s' unknown)"
        local dirty="dirty"
        local origin="$(git config --get remote.origin.url 2>/dev/null || true)"

        if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
            dirty="clean"
        fi

        [[ -n "${origin}" ]] && doctor_status ok "Origin" "${origin}" || doctor_status warn "Origin" "missing"

        doctor_status ok "Root" "${root}"
        doctor_status ok "Branch" "${branch}"
        doctor_status ok "Commit" "${head}"

        [[ "${dirty}" == "clean" ]] && doctor_status ok "Status" "${dirty}" || doctor_status warn "Status" "${dirty}"

    else

        doctor_status ok "Root" "${root}"
        has git && doctor_status warn "Git" "not a git repo" || doctor_status fail "Git" "missing"

    fi

}
doctor_tools () {

    info_ln '==> Tools \n'

    doctor_tool warn "git" git
    doctor_tool warn "gh" gh
    doctor_tool warn "rustup" rustup
    doctor_tool warn "rustc" rustc
    doctor_tool warn "cargo" cargo
    doctor_tool warn "clang" clang
    doctor_tool warn "llvm" llvm-config
    doctor_tool warn "node" node
    doctor_tool warn "npx" npx
    doctor_tool warn "npm" npm

}
doctor_rust () {

    ensure awk
    info_ln '==> Rust \n'

    if ! has rustup; then
        doctor_status fail "rustup" "missing"
        return 0
    fi

    [[ -n "${RUSTFLAGS:-}" ]] && doctor_status ok "RUSTFLAGS" "${RUSTFLAGS}" || doctor_status ok "RUSTFLAGS" "--"
    [[ -n "${RUST_BACKTRACE:-}" ]] && doctor_status ok "RUST_BACKTRACE" "${RUST_BACKTRACE}" || doctor_status ok "RUST_BACKTRACE" "--"

    local active_tc="$(rustup show active-toolchain 2>/dev/null | awk '{print $1}' || true)"
    [[ -n "${active_tc}" ]] && doctor_status ok "active" "${active_tc}" || doctor_status warn "active" "unknown"

    local stable_tc="$(stable_version 2>/dev/null || true)"
    local nightly_tc="$(nightly_version 2>/dev/null || true)"
    local msrv_tc="$(msrv_version 2>/dev/null || true)"

    [[ -n "${stable_tc}" ]] || stable_tc="${RUST_STABLE:-stable}"
    [[ -n "${nightly_tc}" ]] || nightly_tc="${RUST_NIGHTLY:-nightly}"

    doctor_toolchain "stable" "${stable_tc}"
    doctor_toolchain "nightly" "${nightly_tc}"
    [[ -n "${msrv_tc}" ]] && doctor_toolchain "msrv" "${msrv_tc}" || doctor_status warn "msrv" "--"

    if doctor_has_component "${active_tc}" '^(llvm-tools|llvm-tools-preview)($|-)'; then

        local sysroot="$(rustup run "${active_tc}" rustc --print sysroot 2>/dev/null || true)"
        local host="$(rustup run "${active_tc}" rustc -vV 2>/dev/null | awk '/^host: / { print $2; exit }' || true)"
        local bin="${sysroot}/lib/rustlib/${host}/bin/llvm-cov"

        [[ -x "${bin}" ]] || bin="${bin}.exe"

        if [[ -x "${bin}" ]]; then
            local v="$( { "${bin}" --version 2>&1 || true; } | head -n 6 | tr -d '\r' )"
            v="$(doctor_pick_ver_line "${v}")"
            [[ -n "${v}" ]] && doctor_status ok "llvm-tools" "${v}" || doctor_status warn "llvm-tools" "unknown"
        else
            doctor_status warn "llvm-tools" "unknown"
        fi

    else
        doctor_status warn "llvm-tools" "missing"
    fi

    if doctor_has_component "${active_tc}" '^rustfmt($|-)'; then
        doctor_tool warn "rustfmt" rustup run "${active_tc}" rustfmt
    else
        doctor_status warn "rustfmt" "missing"
    fi

    if doctor_has_component "${active_tc}" '^clippy($|-)'; then
        doctor_tool warn "clippy" rustup run "${active_tc}" clippy-driver
    else
        doctor_status warn "clippy" "missing"
    fi

    if doctor_toolchain_installed "${nightly_tc}" && doctor_has_component "${nightly_tc}" '^miri($|-)'; then
        doctor_tool warn "miri" cargo "+${nightly_tc}" miri
    else
        doctor_status warn "miri" "missing"
    fi

    doctor_tool warn "taplo" taplo

}
doctor_cargo () {

    ensure wc tr
    info_ln '==> Cargo \n'

    if ! has cargo; then
        doctor_status fail "cargo" "missing"
        return 0
    fi

    doctor_cargo_sub "nextest"          "nextest"        "cargo-nextest"
    doctor_cargo_sub "llvm-cov"         "llvm-cov"       "cargo-llvm-cov"
    doctor_cargo_sub "cargo-deny"       "deny"           "cargo-deny"
    doctor_cargo_sub "cargo-audit"      "audit"          "cargo-audit"
    doctor_cargo_sub "cargo-semver"     "semver-checks"  "cargo-semver-checks"
    doctor_cargo_sub "cargo-spellcheck" "spellcheck"     "cargo-spellcheck"
    doctor_cargo_sub "cargo-hack"       "hack"           "cargo-hack"
    doctor_cargo_sub "cargo-fuzz"       "fuzz"           "cargo-fuzz"
    doctor_cargo_sub "cargo-upgrade"    "upgrade"        "cargo-upgrade"

    if [[ -d fuzz ]] && [[ -f fuzz/Cargo.toml ]] && has cargo-fuzz; then

        local tc="$(nightly_version 2>/dev/null || true)"
        [[ -n "${tc}" ]] || tc="${RUST_NIGHTLY:-nightly}"

        local targets_cnt="0"
        targets_cnt="$(cargo "+${tc}" fuzz list 2>/dev/null | wc -l | tr -d '[:space:]' || true)"
        [[ "${targets_cnt}" =~ ^[0-9]+$ ]] || targets_cnt="0"

        (( targets_cnt > 0 )) && doctor_status ok "fuzz-targets" "${targets_cnt}" || doctor_status warn "fuzz-targets" "0"

    fi

}
doctor_summary () {

    info_ln '==> Summary \n'

    printf '  ✅ %-18s %s\n' "OK"   "( ${ok} )"
    printf '  ⚠️ %-18s %s\n' "Warn" "( ${warn} )"
    printf '  ❌ %-18s %s\n' "Fail" "( ${fail} )"

    info_ln '==> Analysis \n'

    local face="" msg="" idx=0
    local -a msgs=()

    if (( fail > 0 )); then

        face="🚨"
        msgs=(
            "Hard fail. Stop. Fix. Repeat."
            "Red alert. The compiler is not amused."
            "Failures detected. Reality disagrees with you."
            "Build is down. Ego is optional."
            "This isn't a pipeline… it's a crime scene."
        )
        idx=$(( fail % ${#msgs[@]} ))
        msg="${msgs[$idx]}"

    elif (( warn == 0 )); then

        face="😎"
        msgs=(
            "👌 All is awsome 💯"
            "Clean bill of health."
            "Zero warnings. Maximum swagger."
            "System status: annoyingly perfect."
            "No warnings detected. Proceed with confidence."
        )
        idx=$(( ok % ${#msgs[@]} ))
        msg="${msgs[$idx]}"

    elif (( warn == 1 )); then

        face="🤔"
        msgs=(
            "One warning. I'm watching you."
            "Single warning spotted—probably harmless. Probably."
            "One tiny crack. Not a fire… yet."
            "Almost perfect. Nature is healing."
        )
        idx=$(( warn % ${#msgs[@]} ))
        msg="${msgs[$idx]}"

    elif (( warn == 2 )); then

        face="🟡"
        msgs=(
            "Two warnings. Still fine… but stop tempting fate."
            "Minor turbulence. Fasten your seatbelt."
            "Two warnings—edge of “meh”."
            "Some concerns. Nothing a coffee can't fix."
        )
        idx=$(( warn % ${#msgs[@]} ))
        msg="${msgs[$idx]}"

    else

        face="🧯"
        msgs=(
            "Warning party detected. Please disperse."
            "This is not a build; it's a negotiation."
            "Too many warnings. Your future self is screaming."
            "Status: functional… emotionally unstable."
            "We're in the “it works on my machine” zone."
        )
        idx=$(( warn % ${#msgs[@]} ))
        msg="${msgs[$idx]}"

    fi

    printf '  %s %-18s %s\n' "${face}" "Final Status" "${msg}"
    printf '\n'

}

cmd_doctor () {

    local ok=0 warn=0 fail=0

    doctor_sys
    doctor_github
    doctor_tools
    doctor_rust
    doctor_cargo
    doctor_summary

    (( fail == 0 )) || return 1
    return 0

}
