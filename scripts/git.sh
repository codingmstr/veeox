#!/usr/bin/env bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base.sh"

VX_GITHUB_SSH_KEY="${VX_GITHUB_SSH_KEY:-GITHUB_SSH_KEY}"
VX_GITHUB_TOKEN="${VX_GITHUB_TOKEN:-GITHUB_TOKEN}"
VX_GITHUB_AUTH="${VX_GITHUB_AUTH:-GITHUB_AUTH}"

git_cmd () {

    local kind="${1:-ssh}"
    local ssh_cmd="${2:-}"
    shift 2 || true

    # Never allow interactive prompts (CI + local safety)
    if (( VX_VERBOSE )) && [[ "${kind}" == "http" ]]; then
        local old="${VX_VERBOSE}"
        VX_VERBOSE=0

        if [[ -n "${ssh_cmd}" ]]; then
            GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${ssh_cmd}" run git "$@"
        else
            GIT_TERMINAL_PROMPT=0 run git "$@"
        fi

        VX_VERBOSE="${old}"
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
git_is_semver () {

    [[ "${1}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([\-+][0-9A-Za-z\.\-]+)?$ ]]

}
git_norm_tag () {

    local t="${1}"
    local core="${t}"

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
    local token_env="${5:-${VX_GITHUB_TOKEN}}"

    local kind="" target="" safe="" ssh_cmd=""

    if [[ -z "${auth}" || "${auth}" == "auto" ]]; then
        local env_auth=""
        env_auth="$(env_get "${VX_GITHUB_AUTH}")"
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
            key="$(env_get "${VX_GITHUB_SSH_KEY}")"
            [[ -n "${key}" ]] || key="${VX_SSH_KEY:-}"
        fi

        if [[ -z "${key}" && -f "${HOME}/.ssh/id_ed25519" ]]; then
            key="${HOME}/.ssh/id_ed25519"
        fi

        if [[ -n "${key}" ]]; then
            key="${key/#\~/${HOME}}"
            [[ -f "${key}" ]] || die "Missing ssh key file: ${key}" 2

            # Safer non-interactive SSH + avoids hanging forever
            printf -v ssh_cmd 'ssh -i %q -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2' "${key}"
        fi

        printf '%s\t%s\t%s\t%s\n' "${kind}" "${target}" "${safe}" "${ssh_cmd}"
        return 0

    fi

    if [[ "${auth}" == "http" ]]; then

        kind="http"

        [[ -n "${token}" ]] || token="$(env_get "${token_env}")"
        [[ -n "${token}" ]] || die "Missing token. Use --token or --token-env <VAR> (default: ${VX_GITHUB_TOKEN})." 2

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

    p="${p#/}"
    p="${p%.git}"
    printf '%s.git\n' "${p}"

}
git_init_supports_initial_branch () {

    git init -h 2>/dev/null | grep -q -- '--initial-branch'

}
git_set_default_branch () {

    local branch="${1:-main}"

    git branch -M "${branch}" >/dev/null 2>&1 && return 0
    git symbolic-ref HEAD "refs/heads/${branch}" >/dev/null 2>&1 && return 0
    return 0

}
git_help () {

    cat <<'OUT'
    init             Init git repo + set remote + default branch
    remote           Show remote url (redacted) + protocol

    push             Add/commit + push branch (+ optional tag/release)

    new-branch       Create/switch branch (tracks remote if exists)
    remove-branch    Delete branch locally + remote

    new-release      Create annotated release + push
    remove-release   Delete release locally + remote
OUT
}

cmd_root_version () {

    local toml="${ROOT_DIR}/Cargo.toml"
    [[ -f "${toml}" ]] || return 1

    awk '
        BEGIN { sect=""; pkg="" }

        /^\[workspace\.package\]/ { sect="ws"; next }
        /^\[package\]/           { sect="pkg"; next }
        /^\[/                    { sect=""; next }

        sect=="ws"  && match($0, /^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)"/, m) { print m[1]; exit }
        sect=="pkg" && pkg==""   && match($0, /^[[:space:]]*version[[:space:]]*=[[:space:]]*"([^"]+)"/, m) { pkg=m[1] }

        END { if (pkg!="") print pkg }
    ' "${toml}"

}
cmd_init () {

    cd_root
    need_cmd git

    local repo=""
    local branch="main"
    local remote="origin"
    local auth="" host="" path="" url="" parsed=0

    auth="$(env_get "${VX_GITHUB_AUTH}")"
    [[ -n "${auth}" ]] || auth="ssh"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --auth)         shift || true; auth="${1:-}"; [[ -n "${auth}" ]] || die "Error: --auth requires a value" 2; shift || true ;;
            -b|--branch)    shift || true; branch="${1:-}"; [[ -n "${branch}" ]] || die "Error: --branch requires a value" 2; shift || true ;;
            -r|--remote)    shift || true; remote="${1:-}"; [[ -n "${remote}" ]] || die "Error: --remote requires a value" 2; shift || true ;;
            -h|--help)      log "Usage: vx git-init <url|user/repo> [branch] [remote] [--auth ssh|http|auto]"; return 0 ;;
            --)             shift || true; break ;;
            -* )            die "Unknown arg: $1" 2 ;;
            * )             repo="$1"; shift || true; break ;;
        esac
    done

    [[ -n "${repo}" ]] || die "Usage: vx git-init <url|user/repo> [branch] [remote] [--auth ssh|http|auto]" 2

    [[ -n "${1:-}" ]] && branch="${1}" && shift || true
    [[ -n "${1:-}" ]] && remote="${1}" && shift || true

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
            -r|--remote)
                shift || true
                remote="${1:-}"
                [[ -n "${remote}" ]] || die "Error: --remote requires a value" 2
                shift || true
            ;;
            -h|--help)
                log "Usage: vx remote [--remote <name>]"
                return 0
            ;;
            *)
                die "Unknown arg: $1" 2
            ;;
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

    local auth=""
    auth="$(env_get "${VX_GITHUB_AUTH}")"
    [[ -n "${auth}" ]] || auth="auto"

    local key=""
    local token=""
    local token_env="${VX_GITHUB_TOKEN}"
    local b=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--remote)    shift; remote="${1:-}";    [[ -n "${remote}" ]] || die "Error: --remote requires a value" 2; shift ;;
            --auth)         shift; auth="${1:-}";      [[ -n "${auth}" ]]   || die "Error: --auth requires a value" 2;   shift ;;
            --key)          shift; key="${1:-}";       [[ -n "${key}" ]]    || die "Error: --key requires a value" 2;    shift ;;
            --token)        shift; token="${1:-}";     [[ -n "${token}" ]]  || die "Error: --token requires a value" 2;  shift ;;
            --token-env)    shift; token_env="${1:-}"; [[ -n "${token_env}" ]] || die "Error: --token-env requires a value" 2; shift ;;
            -h|--help)      log "Usage: vx new-branch <branch> [--remote origin] [--auth auto|ssh|http] [--key <path>] [--token <v>|--token-env <VAR>]"; return 0 ;;
            --) shift || true; break ;;
            -*) die "Unknown arg: $1" 2 ;;
            *)  b="$1"; shift || true; break ;;
        esac
    done

    [[ -n "${b}" ]] || die "Usage: vx new-branch <branch> ..." 2

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

    local auth=""
    auth="$(env_get "${VX_GITHUB_AUTH}")"
    [[ -n "${auth}" ]] || auth="auto"

    local key=""
    local token=""
    local token_env="${VX_GITHUB_TOKEN}"
    local b=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--remote)    shift; remote="${1:-}";    [[ -n "${remote}" ]] || die "Error: --remote requires a value" 2; shift ;;
            --auth)         shift; auth="${1:-}";      [[ -n "${auth}" ]]   || die "Error: --auth requires a value" 2;   shift ;;
            --key)          shift; key="${1:-}";       [[ -n "${key}" ]]    || die "Error: --key requires a value" 2;    shift ;;
            --token)        shift; token="${1:-}";     [[ -n "${token}" ]]  || die "Error: --token requires a value" 2;  shift ;;
            --token-env)    shift; token_env="${1:-}"; [[ -n "${token_env}" ]] || die "Error: --token-env requires a value" 2; shift ;;
            -h|--help)      log "Usage: vx remove-branch <branch> [--remote origin] [--auth auto|ssh|http] [--key <path>] [--token <v>|--token-env <VAR>]"; return 0 ;;
            --) shift || true; break ;;
            -*) die "Unknown arg: $1" 2 ;;
            *)  b="$1"; shift || true; break ;;
        esac
    done

    [[ -n "${b}" ]] || die "Usage: vx remove-branch <branch> ..." 2

    local cur=""
    cur="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [[ "${cur}" != "${b}" ]] || die "Can't delete current branch: ${b}" 2

    confirm "Delete branch '${b}' locally and on '${remote}'?" || return 0
    run git branch -D "${b}" >/dev/null 2>&1 || true

    local kind="" target="" safe="" ssh_cmd=""
    IFS=$'\t' read -r kind target safe ssh_cmd < <(git_auth_resolve "${auth}" "${remote}" "${key}" "${token}" "${token_env}")

    git_cmd "${kind}" "${ssh_cmd}" push "${target}" --delete "${b}" >/dev/null 2>&1 || true

}
cmd_new_release () {

    cd_root
    git_repo_guard

    local remote="origin"

    local auth=""
    auth="$(env_get "${VX_GITHUB_AUTH}")"
    [[ -n "${auth}" ]] || auth="auto"

    local key=""
    local token=""
    local token_env="${VX_GITHUB_TOKEN}"
    local tag=""
    local msg=""
    local force=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--remote)    shift; remote="${1:-}";    [[ -n "${remote}" ]] || die "Error: --remote requires a value" 2; shift ;;
            --auth)         shift; auth="${1:-}";      [[ -n "${auth}" ]]   || die "Error: --auth requires a value" 2;   shift ;;
            --key)          shift; key="${1:-}";       [[ -n "${key}" ]]    || die "Error: --key requires a value" 2;    shift ;;
            --token)        shift; token="${1:-}";     [[ -n "${token}" ]]  || die "Error: --token requires a value" 2;  shift ;;
            --token-env)    shift; token_env="${1:-}"; [[ -n "${token_env}" ]] || die "Error: --token-env requires a value" 2; shift ;;
            -f|--force)     force=1; shift ;;
            -m|--message)   shift; msg="${1:-}"; [[ -n "${msg}" ]] || die "Error: --message requires a value" 2; shift ;;
            -h|--help)      log "Usage: vx new-release <tag> [--message <msg>] [--force] [--remote origin] [--auth auto|ssh|http] [--key <path>] [--token <v>|--token-env <VAR>]"; return 0 ;;
            --) shift || true; break ;;
            -*) die "Unknown arg: $1" 2 ;;
            *)  tag="$1"; shift || true; break ;;
        esac
    done

    [[ -n "${tag}" ]] || die "Usage: vx new-release <tag> ..." 2
    [[ -n "${tag}" ]] && tag="$(git_norm_tag "${tag}")"
    [[ -n "${msg}" ]] || msg="release: ${tag}"

    local kind="" target="" safe="" ssh_cmd=""
    IFS=$'\t' read -r kind target safe ssh_cmd < <(git_auth_resolve "${auth}" "${remote}" "${key}" "${token}" "${token_env}")

    if git show-ref --tags --verify --quiet "refs/tags/${tag}"; then
        (( force )) || confirm "Tag '${tag}' exists locally. Replace it?" || die "Cancelled." 2
        git_cmd "${kind}" "${ssh_cmd}" tag -d "${tag}" >/dev/null 2>&1 || true
    fi
    if git_remote_has_tag "${kind}" "${ssh_cmd}" "${target}" "${tag}"; then
        (( force )) || confirm "Tag '${tag}' exists on remote (${remote}). Replace it?" || die "Cancelled." 2
        git_cmd "${kind}" "${ssh_cmd}" push "${target}" --delete "${tag}" >/dev/null 2>&1 || true
    fi

    git_cmd "${kind}" "${ssh_cmd}" tag -a "${tag}" -m "${msg}"
    git_cmd "${kind}" "${ssh_cmd}" push "${target}" "${tag}"

}
cmd_remove_release () {

    cd_root
    git_repo_guard

    local remote="origin"

    local auth=""
    auth="$(env_get "${VX_GITHUB_AUTH}")"
    [[ -n "${auth}" ]] || auth="auto"

    local key=""
    local token=""
    local token_env="${VX_GITHUB_TOKEN}"
    local tag=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--remote)    shift; remote="${1:-}";    [[ -n "${remote}" ]] || die "Error: --remote requires a value" 2; shift ;;
            --auth)         shift; auth="${1:-}";      [[ -n "${auth}" ]]   || die "Error: --auth requires a value" 2;   shift ;;
            --key)          shift; key="${1:-}";       [[ -n "${key}" ]]    || die "Error: --key requires a value" 2;    shift ;;
            --token)        shift; token="${1:-}";     [[ -n "${token}" ]]  || die "Error: --token requires a value" 2;  shift ;;
            --token-env)    shift; token_env="${1:-}"; [[ -n "${token_env}" ]] || die "Error: --token-env requires a value" 2; shift ;;
            -h|--help)      log "Usage: vx remove-release <tag> [--remote origin] [--auth auto|ssh|http] [--key <path>] [--token <v>|--token-env <VAR>]"; return 0 ;;
            --) shift || true; break ;;
            -*) die "Unknown arg: $1" 2 ;;
            *)  tag="$1"; shift || true; break ;;
        esac
    done

    [[ -n "${tag}" ]] || die "Usage: vx remove-release <tag> ..." 2
    [[ -n "${tag}" ]] && tag="$(git_norm_tag "${tag}")"

    confirm "Delete tag '${tag}' locally and on '${remote}'?" || return 0
    run git tag -d "${tag}" >/dev/null 2>&1 || true

    local kind="" target="" safe="" ssh_cmd=""
    IFS=$'\t' read -r kind target safe ssh_cmd < <(git_auth_resolve "${auth}" "${remote}" "${key}" "${token}" "${token_env}")

    git_cmd "${kind}" "${ssh_cmd}" push "${target}" --delete "${tag}" >/dev/null 2>&1 || true

}
cmd_push () {

    cd_root
    git_repo_guard

    local remote="origin"

    local auth=""
    auth="$(env_get "${VX_GITHUB_AUTH}")"
    [[ -n "${auth}" ]] || auth="auto"

    local key=""
    local token=""
    local token_env="${VX_GITHUB_TOKEN}"

    local tag=""
    local branch=""
    local msg="done"
    local force=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--remote)    shift; remote="${1:-}";    [[ -n "${remote}" ]] || die "Error: --remote requires a value" 2; shift ;;
            --auth)         shift; auth="${1:-}";      [[ -n "${auth}" ]]   || die "Error: --auth requires a value" 2;   shift ;;
            --key)          shift; key="${1:-}";       [[ -n "${key}" ]]    || die "Error: --key requires a value" 2;    shift ;;
            --token)        shift; token="${1:-}";     [[ -n "${token}" ]]  || die "Error: --token requires a value" 2;  shift ;;
            --token-env)    shift; token_env="${1:-}"; [[ -n "${token_env}" ]] || die "Error: --token-env requires a value" 2; shift ;;
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
            -b|--branch)    shift; branch="${1:-}";    [[ -n "${branch}" ]] || die "Missing branch" 2;                   shift ;;
            -m|--message)   shift; msg="${1:-}";       [[ -n "${msg}" ]]    || die "Missing message" 2;                  shift ;;
            -f|--force)     force=1; shift ;;
            -h|--help)      log "Usage: vx push [-t|--release <tag>] [-b <branch>] [-m <msg>] [-f] [--remote origin] [--auth auto|ssh|http] [--key <path>] [--token <v>|--token-env <VAR>]"; return 0 ;;
            --) shift || true; break ;;
            *) die "Unknown arg: $1" 2 ;;
        esac
    done

    local kind="" target="" safe="" ssh_cmd=""
    IFS=$'\t' read -r kind target safe ssh_cmd < <(git_auth_resolve "${auth}" "${remote}" "${key}" "${token}" "${token_env}")

    if [[ -z "${branch}" ]]; then
        branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
        [[ -n "${branch}" ]] || branch="main"
    fi
    if [[ "${tag}" == "auto" ]]; then
        local v=""
        v="$(cmd_root_version || true)"
        [[ -n "${v}" ]] || die "Can't detect version from ${ROOT_DIR}/Cargo.toml" 2
        tag="v${v}"
    fi
    if [[ -n "${tag}" ]]; then
        tag="$(git_norm_tag "${tag}")"
        [[ "${msg}" != "done" ]] || msg="Track ${tag} release."
       
        if git_remote_has_tag "${kind}" "${ssh_cmd}" "${target}" "${tag}" && (( force == 0 )); then
            die "Tag exists on remote (${remote}/${tag}). Use -f to overwrite." 2
        fi
    fi

    git_cmd "${kind}" "${ssh_cmd}" add -A

    if ! git_cmd "${kind}" "${ssh_cmd}" diff --cached --quiet >/dev/null 2>&1; then
        git_cmd "${kind}" "${ssh_cmd}" commit -m "${msg}" || die "git commit failed (check user.name/user.email)." 2
    fi
    if [[ -n "${tag}" ]]; then

        git_cmd "${kind}" "${ssh_cmd}" tag -d "${tag}" >/dev/null 2>&1 || true

        if (( force )); then
            git_cmd "${kind}" "${ssh_cmd}" push "${target}" --delete "${tag}" >/dev/null 2>&1 || true
        fi

        git_cmd "${kind}" "${ssh_cmd}" tag -a "${tag}" -m "${msg}"

    fi

    local target_is_url=0
    [[ "${target}" == http://* || "${target}" == https://* ]] && target_is_url=1

    if (( force )); then
        git_cmd "${kind}" "${ssh_cmd}" push --force-with-lease "${target}" "${branch}"
    else
        if (( target_is_url )); then
            git_cmd "${kind}" "${ssh_cmd}" push "${target}" "${branch}"
        else
            if git_upstream_exists_for "${branch}"; then
                git_cmd "${kind}" "${ssh_cmd}" push "${target}" "${branch}"
            else
                git_cmd "${kind}" "${ssh_cmd}" push -u "${target}" "${branch}"
            fi
        fi
    fi

    if [[ -n "${tag}" ]]; then
        if (( force )); then
            git_cmd "${kind}" "${ssh_cmd}" push --force "${target}" "${tag}"
        else
            git_cmd "${kind}" "${ssh_cmd}" push "${target}" "${tag}"
        fi
    fi

    log "OK: pushed via ${kind} -> ${safe}"

}
