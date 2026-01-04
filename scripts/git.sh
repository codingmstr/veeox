#!/usr/bin/env bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base.sh"

GITHUB_SSH_KEY_ENV="${GITHUB_SSH_KEY_ENV:-GITHUB_SSH_KEY}"
GITHUB_TOKEN_ENV="${GITHUB_TOKEN_ENV:-GITHUB_TOKEN}"
GITHUB_AUTH_ENV="${GITHUB_AUTH_ENV:-GITHUB_AUTH}"

git_cmd () {

    local kind="${1:-ssh}"
    local ssh_cmd="${2:-}"
    shift 2 || true

    if (( VERBOSE_ENV )) && [[ "${kind}" == "http" ]]; then

        local old="${VERBOSE_ENV}"
        VERBOSE_ENV=0

        if [[ -n "${ssh_cmd}" ]]; then
            GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${ssh_cmd}" run git "$@"
        else
            GIT_TERMINAL_PROMPT=0 run git "$@"
        fi

        VERBOSE_ENV="${old}"
        return $?

    fi

    if [[ -n "${ssh_cmd}" ]]; then
        GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${ssh_cmd}" run git "$@"
        return $?
    fi

    GIT_TERMINAL_PROMPT=0 run git "$@"

}
git_repo_guard () {

    need_cmd git
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not a git repository." 2

}
git_has_switch () {

    git switch -h >/dev/null 2>&1

}
git_switch () {

    if git_has_switch; then
        git switch "$@"
        return $?
    fi

    if [[ "${1:-}" == "-c" ]]; then

        shift || true
        local b="${1:-}"
        shift || true

        if [[ "${1:-}" == "--track" ]]; then
            shift || true
            local upstream="${1:-}"
            shift || true
            git checkout -b "${b}" --track "${upstream}" "$@"
            return $?
        fi

        git checkout -b "${b}" "$@"
        return $?

    fi

    git checkout "$@"

}
git_has_commit () {

    git rev-parse --verify HEAD >/dev/null 2>&1

}
git_require_remote () {

    local remote="${1:-origin}"

    git remote get-url "${remote}" >/dev/null 2>&1 || \
        die "Remote not found: ${remote}. Run: vx git-init <user/repo>  (or: git remote add ${remote} <url>)" 2

}
git_require_identity () {

    local n="" e=""

    n="$(git config user.name  2>/dev/null || true)"
    e="$(git config user.email 2>/dev/null || true)"

    [[ -n "${n}" && -n "${e}" ]] && return 0

    die "Missing git identity. Set: git config user.name \"Your Name\" && git config user.email \"you@example.com\"" 2

}
git_is_semver () {

    local v="${1:-}"
    local main="" rest="" pre="" build=""

    [[ -n "${v}" ]] || return 1

    if [[ "${v}" == *+* ]]; then
        main="${v%%+*}"
        build="${v#*+}"
    else
        main="${v}"
        build=""
    fi

    if [[ "${main}" == *-* ]]; then
        rest="${main%%-*}"
        pre="${main#*-}"
    else
        rest="${main}"
        pre=""
    fi

    if [[ "${rest}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        :
    else
        return 1
    fi

    if [[ -n "${pre}" ]]; then

        IFS='.' read -r -a ids <<< "${pre}"
        ((${#ids[@]})) || return 1

        local id=""
        for id in "${ids[@]}"; do

            [[ -n "${id}" ]] || return 1
            [[ "${id}" =~ ^[0-9A-Za-z-]+$ ]] || return 1

            if [[ "${id}" =~ ^[0-9]+$ ]]; then
                [[ "${id}" == "0" || "${id}" =~ ^[1-9][0-9]*$ ]] || return 1
            fi

        done

    fi

    if [[ -n "${build}" ]]; then

        IFS='.' read -r -a ids <<< "${build}"
        ((${#ids[@]})) || return 1

        local id=""
        for id in "${ids[@]}"; do
            [[ -n "${id}" ]] || return 1
            [[ "${id}" =~ ^[0-9A-Za-z-]+$ ]] || return 1
        done

    fi

    return 0

}
git_norm_tag () {

    local t="${1:-}"
    local core="${t}"

    [[ -n "${t}" ]] || { printf '%s\n' ""; return 0; }

    if [[ "${t}" == v* ]]; then

        core="${t#v}"
        git_is_semver "${core}" && { printf 'v%s\n' "${core}"; return 0; }
        printf '%s\n' "${t}"
        return 0

    fi

    git_is_semver "${t}" && { printf 'v%s\n' "${t}"; return 0; }
    printf '%s\n' "${t}"

}
git_redact_url () {

    local url="${1:-}"
    local proto="" rest=""

    [[ -n "${url}" ]] || { printf ''; return 0; }

    if [[ "${url}" == http://* || "${url}" == https://* ]]; then

        proto="${url%%://*}://"
        rest="${url#*://}"

        if [[ "${rest}" == *@* ]]; then
            printf '%s***@%s\n' "${proto}" "${rest#*@}"
            return 0
        fi

    fi

    printf '%s\n' "${url}"

}
git_remote_url () {

    local remote="${1:-origin}"
    git remote get-url "${remote}" 2>/dev/null || true

}
git_parse_remote () {

    local url="${1:-}"
    local rest="" host="" path=""

    [[ -n "${url}" ]] || return 1

    if [[ "${url}" == git@*:* ]]; then
        rest="${url#git@}"
        host="${rest%%:*}"
        path="${rest#*:}"
        printf '%s %s\n' "${host}" "${path}"
        return 0
    fi

    if [[ "${url}" == ssh://* ]]; then
        rest="${url#ssh://}"
        rest="${rest#git@}"
        host="${rest%%/*}"
        path="${rest#*/}"
        printf '%s %s\n' "${host}" "${path}"
        return 0
    fi

    if [[ "${url}" == http://* || "${url}" == https://* ]]; then
        rest="${url#*://}"
        [[ "${rest}" == *@* ]] && rest="${rest#*@}"
        host="${rest%%/*}"
        path="${rest#*/}"
        printf '%s %s\n' "${host}" "${path}"
        return 0
    fi

    return 1

}
git_build_https_token_url () {

    local token="${1:-}"
    local host="${2:-}"
    local path="${3:-}"

    [[ -n "${token}" && -n "${host}" && -n "${path}" ]] || return 1
    printf 'https://x-access-token:%s@%s/%s\n' "${token}" "${host}" "${path}"

}
git_upstream_exists_for () {

    local b="${1:-}"
    [[ -n "${b}" ]] || return 1
    git rev-parse --abbrev-ref --symbolic-full-name "${b}@{u}" >/dev/null 2>&1

}
git_remote_has_tag () {

    local kind="${1:-ssh}"
    local ssh_cmd="${2:-}"
    local target="${3:-origin}"
    local tag="${4:-}"

    [[ -n "${tag}" ]] || return 1

    git_cmd "${kind}" "${ssh_cmd}" ls-remote --exit-code --tags --refs "${target}" "refs/tags/${tag}" >/dev/null 2>&1

}
git_remote_has_branch () {

    local kind="${1:-ssh}"
    local ssh_cmd="${2:-}"
    local target="${3:-origin}"
    local b="${4:-}"

    [[ -n "${b}" ]] || return 1

    git_cmd "${kind}" "${ssh_cmd}" ls-remote --exit-code --heads "${target}" "${b}" >/dev/null 2>&1

}
git_auth_resolve () {

    local auth="${1:-auto}"
    local remote="${2:-origin}"
    local key="${3:-}"
    local token="${4:-}"
    local token_env="${5:-${GITHUB_TOKEN_ENV}}"

    local kind="" target="" safe="" ssh_cmd=""

    if [[ -z "${auth}" || "${auth}" == "auto" ]]; then
        local env_auth=""
        env_auth="$(env_get "${GITHUB_AUTH_ENV}")"
        [[ -n "${env_auth}" ]] && auth="${env_auth}" || auth="auto"
    fi

    if [[ "${auth}" == "auto" ]]; then
        if is_ci && { [[ -n "${token}" ]] || [[ -n "$(env_get "${token_env}")" ]]; }; then
            auth="http"
        else
            auth="ssh"
        fi
    fi

    if [[ "${auth}" == "ssh" ]]; then

        kind="ssh"
        target="${remote}"
        safe="${remote}"

        if [[ -z "${key}" ]]; then
            key="$(env_get "${GITHUB_SSH_KEY_ENV}")"
            [[ -n "${key}" ]] || key="${SSH_KEY:-}"
        fi

        if [[ -z "${key}" && -f "${HOME}/.ssh/id_ed25519" ]]; then
            key="${HOME}/.ssh/id_ed25519"
        fi

        ssh_cmd='ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2'

        if [[ -n "${key}" ]]; then

            key="${key/#\~/${HOME}}"
            [[ -f "${key}" ]] || die "Missing ssh key file: ${key}" 2

            printf -v ssh_cmd 'ssh -i %q -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2' "${key}"

        fi

        printf '%s\t%s\t%s\t%s\n' "${kind}" "${target}" "${safe}" "${ssh_cmd}"
        return 0

    fi

    if [[ "${auth}" == "http" ]]; then

        kind="http"

        [[ -n "${token}" ]] || token="$(env_get "${token_env}")"
        [[ -n "${token}" ]] || die "Missing token. Use --token or --token-env <VAR> (default: ${GITHUB_TOKEN_ENV})." 2

        local cur="" host="" path="" url=""

        cur="$(git_remote_url "${remote}")"
        [[ -n "${cur}" ]] || die "Remote not found: ${remote}" 2

        read -r host path < <(git_parse_remote "${cur}") || die "Can't parse remote url: $(git_redact_url "${cur}")" 2
        url="$(git_build_https_token_url "${token}" "${host}" "${path}")" || die "Can't build token url" 2

        target="${url}"
        safe="https://***@${host}/${path}"

        printf '%s\t%s\t%s\t%s\n' "${kind}" "${target}" "${safe}" ""
        return 0

    fi

    die "Unknown auth: ${auth} (use auto|ssh|http)" 2

}
git_build_ssh_url () {

    local host="${1:-}"
    local path="${2:-}"

    [[ -n "${host}" && -n "${path}" ]] || return 1
    printf 'git@%s:%s\n' "${host}" "${path}"

}
git_build_https_url () {

    local host="${1:-}"
    local path="${2:-}"

    [[ -n "${host}" && -n "${path}" ]] || return 1
    printf 'https://%s/%s\n' "${host}" "${path}"

}
git_norm_path_git () {

    local p="${1:-}"
    [[ -n "${p}" ]] || { printf ''; return 0; }

    p="${p%/}"
    p="${p#/}"
    p="${p%.git}"

    printf '%s.git\n' "${p}"

}
git_init_supports_initial_branch () {

    ( git init -h 2>&1 || true ) | grep -q -- '--initial-branch'

}
git_set_default_branch () {

    local branch="${1:-main}"

    git branch -M "${branch}" >/dev/null 2>&1 && return 0
    git symbolic-ref HEAD "refs/heads/${branch}" >/dev/null 2>&1 && return 0
    return 0

}
git_guard_no_unborn_nested_repos () {

    need_cmd find

    local root="${1:-.}"
    local d="" repo=""

    while IFS= read -r -d '' d; do

        repo="${d%/.git}"

        [[ "${repo}" == "${ROOT_DIR}" ]] && continue

        git -C "${repo}" rev-parse --verify HEAD >/dev/null 2>&1 && continue

        die "Nested git repo with no commit checked out: ${repo}. Remove its .git or initialize/commit it." 2

    done < <(find "${root}" -mindepth 2 -name .git -type d -print0 2>/dev/null)

}
git_root_version () {

    need_cmd awk

    local v="" toml="${ROOT_DIR}/Cargo.toml"
    [[ -f "${toml}" ]] || die "Can't detect version: missing file: ${toml}" 2

    v="$(
        awk '
            BEGIN {
                sect=""
                ws=""
                pkg=""
            }

            /^\[workspace\.package\][[:space:]]*$/ { sect="ws"; next }
            /^\[package\][[:space:]]*$/           { sect="pkg"; next }
            /^\[[^]]+\][[:space:]]*$/             { sect=""; next }

            sect=="ws"  && ws==""  && match($0, /^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)"/, m) { ws=m[1]; next }
            sect=="pkg" && pkg=="" && match($0, /^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)"/, m) { pkg=m[1]; next }

            END {
                if (ws != "")  { print ws;  exit 0 }
                if (pkg != "") { print pkg; exit 0 }
                exit 1
            }
        ' "${toml}" 2>/dev/null
    )" || die "Can't detect version from ${toml}." 2

    [[ -n "${v}" ]] || die "Can't detect version from ${toml}." 2
    printf '%s\n' "${v}"

}
help_git () {

    cat <<'OUT'
    Git:
        init <url|user/repo> [--branch main] [--remote origin] [--auth ssh|http|auto]
            Init repo (if missing), set default branch, and set remote.

        remote [--remote origin]
            Show remote url (redacted) + protocol.

        push [options]
            Add/commit + push branch. Optional: tag release + changelog.

            -r, --remote <name>         Default: origin
            -b, --branch <name>         Default: current (fallback: main)
            -m, --message <msg>         Commit/tag message
            -f, --force                 Force push (with lease) + overwrite tag
            --auth <auto|ssh|http>      Default: auto
            --key <path>                SSH key path
            --token <value>             Token value (http mode)
            --token-env <VAR>           Token env var name (default: GITHUB_TOKEN)

            -t, --tag <tag>             Tag name (auto normalizes to vX.Y.Z if semver)
            --release[=<tag>]           Same as --tag; if omitted uses v<root Cargo.toml version>
            -ch, --changelog            Prepend CHANGELOG entry (requires tag/release)

        changelog <tag> [message]
            Write changelog block at top (idempotent, ensures '# Changelog').

        new-branch <name> [options]
        remove-branch <name> [options]

        new-release <tag> [options]
        remove-release <tag> [options]

    Env:
        GITHUB_AUTH        auto|ssh|http
        GITHUB_SSH_KEY     path to ssh key
        GITHUB_TOKEN       token for http auth
OUT
}

cmd_changelog () {

    cd_root
    need_cmd grep
    need_cmd mktemp
    need_cmd mv
    need_cmd date
    need_cmd tail

    local tag="${1:-unreleased}"
    local msg="${2:-}"
    local file="${ROOT_DIR}/CHANGELOG.md"
    local day="" tmp="" header="" block="" sha="" first=""

    [[ -n "${msg}" ]] || msg="Track ${tag} release."

    msg="${msg//$'\r'/ }"
    msg="${msg//$'\n'/ }"

    day="$(date -u +%Y-%m-%d)"

    [[ "${tag}" =~ ^v[0-9] ]] && tag="${tag#v}"
    header="## 💥 ${tag} ( ${day} )"

    has_cmd git && sha="$(git rev-parse --short HEAD 2>/dev/null || true)"
    if [[ -n "${sha}" ]]; then
        block="${header}"$'\n\n'"- ${msg} ( commit: ${sha} )"$'\n'
    else
        block="${header}"$'\n\n'"- ${msg}"$'\n'
    fi

    tmp="$(mktemp)" || die "changelog: mktemp failed" 2

    if [[ -f "${file}" ]]; then

        local top=""
        IFS= read -r top < "${file}" 2>/dev/null || true

        if [[ "${top}" != "# Changelog" ]]; then
            { printf '%s\n\n' "# Changelog"; cat "${file}"; } > "${tmp}"
            mv -f -- "${tmp}" "${file}"
            tmp="$(mktemp)" || die "changelog: mktemp failed" 2
        fi

        first="$(tail -n +2 "${file}" 2>/dev/null | grep -m1 -E '^[[:space:]]*## ' || true)"
        if [[ "${first}" == "${header}" ]]; then
            log "changelog: already written -> skip"
            return 0
        fi

        {
            printf '%s\n' "# Changelog"
            printf '\n'
            printf '%s' "${block}"
            printf '\n'
            tail -n +2 "${file}"
        } > "${tmp}"

    else

        {
            printf '%s\n\n' "# Changelog"
            printf '%s' "${block}"
            printf '\n'
        } > "${tmp}"

    fi

    mv -f -- "${tmp}" "${file}"
    log "changelog: updated ${file}"

}
cmd_init () {

    cd_root
    need_cmd git

    local repo=""
    local branch="main"
    local remote="origin"
    local auth="" host="" path="" url="" parsed=0

    auth="$(env_get "${GITHUB_AUTH_ENV}")"
    [[ -n "${auth}" ]] || auth="ssh"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --auth)         shift || true; auth="${1:-}";   [[ -n "${auth}" ]]   || die "Error: --auth requires a value" 2;   shift || true ;;
            --repo)         shift || true; repo="${1:-}";   [[ -n "${repo}" ]]   || die "Error: --repo requires a value" 2;   shift || true ;;
            -b|--branch)    shift || true; branch="${1:-}"; [[ -n "${branch}" ]] || die "Error: --branch requires a value" 2; shift || true ;;
            -r|--remote)    shift || true; remote="${1:-}"; [[ -n "${remote}" ]] || die "Error: --remote requires a value" 2; shift || true ;;
            -h|--help)      log "Usage: git-init <url|user/repo> [--branch main] [--remote origin] [--auth ssh|http|auto]"; return 0 ;;
            --)             shift || true; break ;;
            -*)             die "Unknown arg: $1" 2 ;;
            *)              [[ -z "${repo}" ]] && repo="$1"; shift || true; break ;;
        esac
    done

    [[ -n "${repo}" ]] || die "Usage: git-init <url|user/repo> [--branch main] [--remote origin] [--auth ssh|http|auto]" 2

    case "${auth}" in
        ssh|http|auto) ;;
        *) die "Unknown auth: ${auth} (use ssh|http|auto)" 2 ;;
    esac

    [[ "${auth}" == "auto" ]] && auth="ssh"

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then

        if git_init_supports_initial_branch; then
            run git init -b "${branch}"
        else
            run git init
            git_set_default_branch "${branch}"
        fi

    fi

    if [[ "${repo}" != *"://"* && "${repo}" != git@*:* && "${repo}" != ssh://* && "${repo}" == */* ]]; then
        host="github.com"
        path="${repo}"
        parsed=1
    else
        if read -r host path < <(git_parse_remote "${repo}"); then
            parsed=1
        fi
    fi

    if (( parsed )); then

        path="$(git_norm_path_git "${path}")"

        if [[ "${auth}" == "ssh" ]]; then
            url="$(git_build_ssh_url "${host}" "${path}")" || die "Can't build ssh url" 2
        else
            url="$(git_build_https_url "${host}" "${path}")" || die "Can't build https url" 2
        fi

    else

        url="${repo}"

    fi

    if git remote get-url "${remote}" >/dev/null 2>&1; then
        run git remote set-url "${remote}" "${url}"
    else
        run git remote add "${remote}" "${url}"
    fi

    git_set_default_branch "${branch}"
    log "OK: branch='${branch}', remote='${remote}' -> $(git_redact_url "${url}")"

}
cmd_remote () {

    cd_root
    git_repo_guard

    local remote="origin"
    local url=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--remote) shift || true; remote="${1:-}"; [[ -n "${remote}" ]] || die "Error: --remote requires a value" 2; shift || true ;;
            -h|--help)   log "Usage: remote [--remote <name>]"; return 0 ;;
            *)           die "Unknown arg: $1" 2 ;;
        esac
    done

    url="$(git_remote_url "${remote}")"
    [[ -n "${url}" ]] || die "Remote not found: ${remote}" 2

    log "${remote}: $(git_redact_url "${url}")"

    if [[ "${url}" == https://* || "${url}" == http://* ]]; then
        log "Protocol: HTTPS"
        return 0
    fi

    if [[ "${url}" == git@*:* || "${url}" == ssh://* ]]; then
        log "Protocol: SSH"
        return 0
    fi

    log "Protocol: unknown"

}
cmd_new_branch () {

    cd_root
    git_repo_guard

    local remote="origin"
    local key="" token="" b="" token_env="${GITHUB_TOKEN_ENV}"
    local auth="$(env_get "${GITHUB_AUTH_ENV}")"

    [[ -n "${auth}" ]] || auth="auto"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--remote)    shift; remote="${1:-}"; [[ -n "${remote}" ]] || die "Error: --remote requires a value" 2; shift ;;
            --auth)         shift; auth="${1:-}";   [[ -n "${auth}" ]]   || die "Error: --auth requires a value" 2;   shift ;;
            --key)          shift; key="${1:-}";    [[ -n "${key}" ]]    || die "Error: --key requires a value" 2;    shift ;;
            --token)        shift; token="${1:-}";  [[ -n "${token}" ]]  || die "Error: --token requires a value" 2;  shift ;;
            --token-env)    shift; token_env="${1:-}"; [[ -n "${token_env}" ]] || die "Error: --token-env requires a value" 2; shift ;;
            -h|--help)      log "Usage: new-branch <branch> [--remote origin] [--auth auto|ssh|http] [--key <path>] [--token <v>|--token-env <VAR>]"; return 0 ;;
            --)             shift || true; break ;;
            -*)             die "Unknown arg: $1" 2 ;;
            *)              b="$1"; shift || true; break ;;
        esac
    done

    [[ -n "${b}" ]] || die "Usage: new-branch <branch> ..." 2

    git_require_remote "${remote}"

    local kind="" target="" safe="" ssh_cmd=""
    IFS=$'\t' read -r kind target safe ssh_cmd < <(git_auth_resolve "${auth}" "${remote}" "${key}" "${token}" "${token_env}")

    if git show-ref --verify --quiet "refs/heads/${b}"; then
        git_switch "${b}"
        return 0
    fi

    if git_remote_has_branch "${kind}" "${ssh_cmd}" "${target}" "${b}"; then

        git_cmd "${kind}" "${ssh_cmd}" fetch "${target}" "refs/heads/${b}:refs/remotes/${remote}/${b}" >/dev/null 2>&1 || true
        git_switch -c "${b}" --track "${remote}/${b}"
        return 0

    fi

    git_switch -c "${b}"

}
cmd_remove_branch () {

    cd_root
    git_repo_guard

    local remote="origin"
    local key="" token="" b="" token_env="${GITHUB_TOKEN_ENV}"
    local auth="$(env_get "${GITHUB_AUTH_ENV}")"

    [[ -n "${auth}" ]] || auth="auto"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--remote)    shift; remote="${1:-}"; [[ -n "${remote}" ]] || die "Error: --remote requires a value" 2; shift ;;
            --auth)         shift; auth="${1:-}";   [[ -n "${auth}" ]]   || die "Error: --auth requires a value" 2;   shift ;;
            --key)          shift; key="${1:-}";    [[ -n "${key}" ]]    || die "Error: --key requires a value" 2;    shift ;;
            --token)        shift; token="${1:-}";  [[ -n "${token}" ]]  || die "Error: --token requires a value" 2;  shift ;;
            --token-env)    shift; token_env="${1:-}"; [[ -n "${token_env}" ]] || die "Error: --token-env requires a value" 2; shift ;;
            -h|--help)      log "Usage: remove-branch <branch> [--remote origin] [--auth auto|ssh|http] [--key <path>] [--token <v>|--token-env <VAR>]"; return 0 ;;
            --)             shift || true; break ;;
            -*)             die "Unknown arg: $1" 2 ;;
            *)              b="$1"; shift || true; break ;;
        esac
    done

    [[ -n "${b}" ]] || die "Usage: remove-branch <branch> ..." 2

    git_require_remote "${remote}"

    local cur=""
    cur="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [[ "${cur}" != "${b}" ]] || die "Can't delete current branch: ${b}" 2

    confirm "Delete branch '${b}' locally and on '${remote}'?" || return 0

    run git branch -D "${b}" >/dev/null 2>&1 || true

    local kind="" target="" safe="" ssh_cmd=""
    IFS=$'\t' read -r kind target safe ssh_cmd < <(git_auth_resolve "${auth}" "${remote}" "${key}" "${token}" "${token_env}")

    git_cmd "${kind}" "${ssh_cmd}" push "${target}" --delete "${b}" >/dev/null 2>&1 || true

}
cmd_remove_release () {

    cd_root
    git_repo_guard

    local remote="origin"
    local auth="$(env_get "${GITHUB_AUTH_ENV}")"
    [[ -n "${auth}" ]] || auth="auto"

    local key=""
    local token=""
    local token_env="${GITHUB_TOKEN_ENV}"
    local tag=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--remote)    shift; remote="${1:-}"; [[ -n "${remote}" ]] || die "Error: --remote requires a value" 2; shift ;;
            --auth)         shift; auth="${1:-}";   [[ -n "${auth}" ]]   || die "Error: --auth requires a value" 2;   shift ;;
            --key)          shift; key="${1:-}";    [[ -n "${key}" ]]    || die "Error: --key requires a value" 2;    shift ;;
            --token)        shift; token="${1:-}";  [[ -n "${token}" ]]  || die "Error: --token requires a value" 2;  shift ;;
            --token-env)    shift; token_env="${1:-}"; [[ -n "${token_env}" ]] || die "Error: --token-env requires a value" 2; shift ;;
            -h|--help)      log "Usage: remove-release <tag> [--remote origin] [--auth auto|ssh|http] [--key <path>] [--token <v>|--token-env <VAR>]"; return 0 ;;
            --)             shift || true; break ;;
            -*)             die "Unknown arg: $1" 2 ;;
            *)              tag="$1"; shift || true; break ;;
        esac
    done

    [[ -n "${tag}" ]] || die "Usage: remove-release <tag> ..." 2
    tag="$(git_norm_tag "${tag}")"

    confirm "Delete tag '${tag}' locally and on '${remote}'?" || return 0
    run git tag -d "${tag}" >/dev/null 2>&1 || true

    git_require_remote "${remote}"

    local kind="" target="" safe="" ssh_cmd=""
    IFS=$'\t' read -r kind target safe ssh_cmd < <(git_auth_resolve "${auth}" "${remote}" "${key}" "${token}" "${token_env}")

    git_cmd "${kind}" "${ssh_cmd}" push "${target}" --delete "${tag}" >/dev/null 2>&1 || true

}
cmd_new_release () {

    local tag="${1:-}"
    shift || true
    [[ -n "${tag}" ]] || die "Usage: new-release <tag> [push options...]" 2

    cmd_push --release "${tag}" "$@"

}
cmd_push () {

    cd_root
    git_repo_guard

    local remote="origin"
    local auth=""

    auth="$(env_get "${GITHUB_AUTH_ENV}")"
    [[ -n "${auth}" ]] || auth="auto"

    local key=""
    local token=""
    local token_env="${GITHUB_TOKEN_ENV}"

    local tag=""
    local branch=""
    local msg="done"
    local force=0
    local changelog=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--remote)     shift; remote="${1:-}"; [[ -n "${remote}" ]] || die "Error: --remote requires a value" 2; shift ;;
            --auth)          shift; auth="${1:-}";   [[ -n "${auth}" ]]   || die "Error: --auth requires a value" 2;   shift ;;
            --key)           shift; key="${1:-}";    [[ -n "${key}" ]]    || die "Error: --key requires a value" 2;    shift ;;
            --token)         shift; token="${1:-}";  [[ -n "${token}" ]]  || die "Error: --token requires a value" 2;  shift ;;
            --token-env)     shift; token_env="${1:-}"; [[ -n "${token_env}" ]] || die "Error: --token-env requires a value" 2; shift ;;
            -b|--branch)     shift; branch="${1:-}"; [[ -n "${branch}" ]] || die "Missing branch" 2; shift ;;
            -m|--message)    shift; msg="${1:-}";    [[ -n "${msg}" ]]    || die "Missing message" 2; shift ;;
            -f|--force)      force=1; shift ;;
            -ch|--changelog) changelog=1; shift ;;
            -t|--tag|--release)
                shift || true
                if [[ -n "${1:-}" && "${1:-}" != -* ]]; then
                    tag="${1}"
                    shift || true
                else
                    tag="auto"
                fi
            ;;
            --tag=*|--release=*)
                tag="${1#*=}"
                [[ -n "${tag}" ]] || tag="auto"
                shift || true
            ;;
            -h|--help)
                log "Usage: push [-t|--release <tag>] [-b <branch>] [-m <msg>] [-f] [--remote origin] [--auth auto|ssh|http] [--key <path>] [--token <v>|--token-env <VAR>] [-ch|--changelog]"
                return 0
            ;;
            --) shift || true; break ;;
            *) die "Unknown arg: $1" 2 ;;
        esac
    done

    git_require_remote "${remote}"

    local kind="" target="" safe="" ssh_cmd=""
    IFS=$'\t' read -r kind target safe ssh_cmd < <(git_auth_resolve "${auth}" "${remote}" "${key}" "${token}" "${token_env}")
    [[ -n "${kind}" && -n "${target}" ]] || die "Failed to resolve git auth for remote '${remote}'." 2

    if [[ -z "${branch}" ]]; then
        branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
        [[ -n "${branch}" ]] || branch="main"
    fi

    if [[ "${tag}" == "auto" ]]; then
        local v=""
        v="$(git_root_version)"
        tag="v${v}"
    fi

    if [[ -n "${tag}" ]]; then
        tag="$(git_norm_tag "${tag}")"
        [[ "${msg}" != "done" ]] || msg="Track ${tag} release."
    fi

    git_guard_no_unborn_nested_repos "${ROOT_DIR}"

    git_cmd "${kind}" "${ssh_cmd}" add -A || die "git add failed." 2

    if git_cmd "${kind}" "${ssh_cmd}" diff --cached --quiet >/dev/null 2>&1; then

        git_has_commit || die "Nothing to push: no commits yet. Make changes then run: vx push" 2

    else

        git_require_identity
        git_cmd "${kind}" "${ssh_cmd}" commit -m "${msg}" || die "git commit failed." 2

    fi

    if [[ -n "${tag}" ]]; then

        if git_remote_has_tag "${kind}" "${ssh_cmd}" "${target}" "${tag}" && (( force == 0 )); then
            log "Tag exists on remote (${remote}/${tag}). Use -f to overwrite."
            tag=""
            changelog=0
        else
            if (( changelog )); then
                cmd_changelog "${tag}" "${msg}"
                git_cmd "${kind}" "${ssh_cmd}" add -A

                if ! git_cmd "${kind}" "${ssh_cmd}" diff --cached --quiet >/dev/null 2>&1; then
                    git_require_identity
                    git_cmd "${kind}" "${ssh_cmd}" commit -m "changelog: ${tag}" || die "git commit failed." 2
                fi
            fi
        fi

    fi

    local target_is_url=0
    [[ "${target}" == http://* || "${target}" == https://* ]] && target_is_url=1

    if (( force )); then

        git_cmd "${kind}" "${ssh_cmd}" fetch "${target}" "${branch}" >/dev/null 2>&1 || true

        git_cmd "${kind}" "${ssh_cmd}" push --force-with-lease "${target}" "${branch}" || \
            die "push rejected (even with -f). Remote ahead; fetch/pull first." 2

    else

        if (( target_is_url )); then

            git_cmd "${kind}" "${ssh_cmd}" push "${target}" "${branch}" || \
                die "push rejected. Remote has commits you don't have. Run: git pull --rebase ${remote} ${branch}" 2

        else

            if git_upstream_exists_for "${branch}"; then
                git_cmd "${kind}" "${ssh_cmd}" push "${target}" "${branch}" || \
                    die "push rejected. Run: git pull --rebase ${remote} ${branch}" 2
            else
                git_cmd "${kind}" "${ssh_cmd}" push -u "${target}" "${branch}" || \
                    die "push rejected. Run: git pull --rebase ${remote} ${branch}" 2
            fi

        fi

    fi

    if [[ -n "${tag}" ]]; then

        git_cmd "${kind}" "${ssh_cmd}" tag -d "${tag}" >/dev/null 2>&1 || true

        if (( force )); then
            git_cmd "${kind}" "${ssh_cmd}" push "${target}" --delete "${tag}" >/dev/null 2>&1 || true
        fi

        git_cmd "${kind}" "${ssh_cmd}" tag -a "${tag}" -m "${msg}" || die "tag create failed." 2

        if (( force )); then
            git_cmd "${kind}" "${ssh_cmd}" push --force "${target}" "${tag}" || die "tag push failed." 2
        else
            git_cmd "${kind}" "${ssh_cmd}" push "${target}" "${tag}" || die "tag push failed." 2
        fi

    fi

    log "OK: pushed via ${kind} -> ${safe}"

}
