#!/usr/bin/env bash
set -Eeuo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base.sh"

usage () {

    printf '%s\n' \
        "" \
        "Usage:" \
        "  ./scripts/install.sh [--yes|-y] [--alias|-a NAME] [--user USER] [--repo REPO] [--name NAME] [--branch BRANCH]" \
        "                    [--github-base URL] [--discord URL] [--docs URL] [--site URL]" \
        "" \
        "Options:" \
        "  -a, --alias NAME       Command name (default: vx)" \
        "      --user  USER       GitHub user/org (placeholders + URLs)" \
        "      --repo  REPO       GitHub repo name (placeholders + URLs)" \
        "      --name  NAME       Project/workspace name (placeholders)" \
        "      --branch BRANCH    Default branch (used for blob/tree URLs)" \
        "      --github-base URL  GitHub base (default: https://github.com)" \
        "      --discord URL      Discord invite/server URL" \
        "      --docs URL         Docs URL" \
        "      --site URL         Project website URL" \
        "  -y, --yes              Non-interactive (assume yes)" \
        "  -h, --help             Show help" \
        ""

}
home_dir () {

    local h="${HOME:-}"

    if [[ -n "${h}" ]]; then
        printf '%s' "${h}"
        return 0
    fi

    h="$(cd ~ 2>/dev/null && pwd || true)"
    [[ -n "${h}" ]] || die "HOME not set; cannot resolve home directory." 2

    printf '%s' "${h}"

}
ensure_line_once () {

    ensure_pkg grep

    local file="${1:-}"
    local line="${2:-}"

    [[ -n "${file}" ]] || die "ensure_line_once: missing file" 2
    [[ -n "${line}" ]] || die "ensure_line_once: missing line" 2

    [[ -L "${file}" ]] && die "Refusing to modify symlink: ${file}" 2

    ensure_file "${file}"

    LC_ALL=C grep -Fqx -- "${line}" "${file}" 2>/dev/null && return 0
    LC_ALL=C grep -Fqx -- "${line}"$'\r' "${file}" 2>/dev/null && return 0

    printf '%s\n' "${line}" >> "${file}" || die "Failed writing: ${file}" 2

}
ensure_path_once () {

    local rc="${1:-}"
    local alias_name="${2:-vx}"

    [[ -n "${rc}" ]] || die "ensure_path_once: missing rc" 2
    [[ -L "${rc}" ]] && die "Refusing to modify symlink: ${rc}" 2

    ensure_file "${rc}"
    ensure_line_once "${rc}" "# ${alias_name}"

    case "${rc}" in
        */.config/fish/config.fish)
            ensure_line_once "${rc}" 'set -gx PATH $HOME/.local/bin $PATH'
        ;;
        *)
            ensure_line_once "${rc}" 'export PATH="$HOME/.local/bin:$PATH"'
        ;;
    esac

}
install_launcher () {

    ensure_pkg chmod mkdir

    local root="${1:-}"
    local alias_name="${2:-vx}"

    [[ -n "${root}" ]] || die "install_launcher: missing root" 2
    is_valid_alias "${alias_name}" || die "Invalid alias: ${alias_name}" 2

    local run_sh="${root}/scripts/run.sh"
    [[ -f "${run_sh}" ]] || die "Missing: ${run_sh}" 2

    chmod +x "${run_sh}" >/dev/null 2>&1 || true

    local home="$(home_dir)"

    local bin_dir="${home}/.local/bin"
    ensure_dir "${bin_dir}"

    local bin="${bin_dir}/${alias_name}"

    if [[ -e "${bin}" && ! -f "${bin}" ]]; then
        die "Refusing: target exists but not a file: ${bin}" 2
    fi
    if [[ -L "${bin}" ]]; then
        die "Refusing to overwrite symlink: ${bin}" 2
    fi
    if [[ -e "${bin}" ]] && ! (( YES_ENV )); then
        confirm "Overwrite ${bin}?" || die "Canceled." 2
    fi

    local root_q=""
    printf -v root_q '%q' "${root}"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -Eeuo pipefail' \
        '' \
        "ROOT=${root_q}" \
        '' \
        'exec /usr/bin/env bash "${ROOT}/scripts/run.sh" "$@"' \
        > "${bin}" || die "Failed writing: ${bin}" 2

    chmod +x "${bin}" || die "chmod failed: ${bin}" 2
    printf '%s\n' "${bin}"

}
detect_default_branch () {

    local root="${1:-}"
    local b=""

    if has git && [[ -e "${root}/.git" ]]; then

        local line=""
        while IFS= read -r line || [[ -n "${line}" ]]; do
            case "${line}" in
                *"HEAD branch:"*)
                    b="${line##*: }"
                    break
                ;;
            esac
        done < <(cd -- "${root}" && git remote show origin 2>/dev/null || true)

        if [[ -z "${b}" ]]; then
            b="$(cd -- "${root}" && git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
            [[ "${b}" == "HEAD" ]] && b=""
        fi

    fi

    [[ -n "${b}" ]] || b="main"
    printf '%s' "${b}"

}
gh_blob_url () {

    local repo_url="${1:-}"
    local branch="${2:-}"
    local rel="${3:-}"

    rel="${rel#/}"
    printf '%s/blob/%s/%s' "${repo_url}" "${branch}" "${rel}"

}
gh_tree_url () {

    local repo_url="${1:-}"
    local branch="${2:-}"
    local rel="${3:-}"

    rel="${rel#/}"
    printf '%s/tree/%s/%s' "${repo_url}" "${branch}" "${rel}"

}
ph_replace () {

    local root="${1:-}"
    local key="${2:-}"
    local val="${3-}"

    [[ -n "${root}" ]] || return 0
    [[ -n "${key}"  ]] || return 0
    [[ -n "${val}"  ]] || return 0

    local rc=0

    if (( VERBOSE_ENV )); then
        replace_all "${key}" "${val}" "${root}"
    else
        replace_all "${key}" "${val}" "${root}" >/dev/null 2>&1
    fi

    rc=$?

    case "${rc}" in
        0|1) return 0 ;;
        2)   die "placeholders: failed replacing ${key}" 2 ;;
        *)   die "placeholders: unexpected rc=${rc} for ${key}" 2 ;;
    esac

}
apply_placeholders () {

    local alias_name="${2:-}"
    local root="${1:-}"
    local user="${3-}"
    local name="${4-}"
    local repo="${5-}"
    local branch="${6-}"
    local github_base="${7:-}"
    local discord_url="${8-}"
    local docs_url="${9-}"
    local site_url="${10-}"

    ph_replace "${root}" "__ALIAS__" "${alias_name}"
    ph_replace "${root}" "__alias__" "${alias_name}"

    ph_replace "${root}" "__BRANCH__" "${branch}"
    ph_replace "${root}" "__branch__" "${branch}"

    [[ -n "${user}" ]] && ph_replace "${root}" "__USER__" "${user}"
    [[ -n "${user}" ]] && ph_replace "${root}" "__user__" "${user}"

    [[ -n "${repo}" ]] && ph_replace "${root}" "__REPO__" "${repo}"
    [[ -n "${repo}" ]] && ph_replace "${root}" "__repo__" "${repo}"

    [[ -n "${name}" ]] && ph_replace "${root}" "__NAME__" "${name}"
    [[ -n "${name}" ]] && ph_replace "${root}" "__name__" "${name}"

    [[ -n "${docs_url}" ]] && ph_replace "${root}" "__DOCS_URL__" "${docs_url}"
    [[ -n "${docs_url}" ]] && ph_replace "${root}" "__docs_url__" "${docs_url}"

    [[ -n "${site_url}" ]] && ph_replace "${root}" "__SITE_URL__" "${site_url}"
    [[ -n "${site_url}" ]] && ph_replace "${root}" "__site_url__" "${site_url}"

    [[ -n "${discord_url}" ]] && ph_replace "${root}" "__DISCORD_URL__" "${discord_url}"
    [[ -n "${discord_url}" ]] && ph_replace "${root}" "__discord_url__" "${discord_url}"

    if [[ -n "${user}" && -n "${repo}" ]]; then

        local security_url="" support_url="" readme_url="" contributing_url=""
        local coc_url="" changelog_url="" pr_tmpl_url="" issue_templates_url=""

        local repo_url="${github_base}/${user}/${repo}"
        local issues_url="${repo_url}/issues"
        local new_issue_url="${repo_url}/issues/new/choose"
        local discussions_url="${repo_url}/discussions"
        local community_url="${repo_url}/graphs/community"

        local categories_url="${repo_url}/discussions/categories"
        local announcements_url="${repo_url}/discussions/categories/announcements"
        local general_url="${repo_url}/discussions/categories/general"
        local ideas_url="${repo_url}/discussions/categories/ideas"
        local polls_url="${repo_url}/discussions/categories/polls"
        local qa_url="${repo_url}/discussions/categories/q-a"
        local show_and_tell_url="${repo_url}/discussions/categories/show-and-tell"

        ph_replace "${root}" "__REPO_URL__" "${repo_url}"
        ph_replace "${root}" "__repo_url__" "${repo_url}"

        ph_replace "${root}" "__ISSUES_URL__" "${issues_url}"
        ph_replace "${root}" "__issues_url__" "${issues_url}"

        ph_replace "${root}" "__NEW_ISSUE_URL__" "${new_issue_url}"
        ph_replace "${root}" "__new_issue_url__" "${new_issue_url}"

        ph_replace "${root}" "__DISCUSSIONS_URL__" "${discussions_url}"
        ph_replace "${root}" "__discussions_url__" "${discussions_url}"

        ph_replace "${root}" "__COMMUNITY_URL__" "${community_url}"
        ph_replace "${root}" "__community_url__" "${community_url}"

        ph_replace "${root}" "__CATEGORIES_URL__" "${categories_url}"
        ph_replace "${root}" "__categories_url__" "${categories_url}"

        ph_replace "${root}" "__ANNOUNCEMENTS_URL__" "${announcements_url}"
        ph_replace "${root}" "__announcements_url__" "${announcements_url}"

        ph_replace "${root}" "__GENERAL_URL__" "${general_url}"
        ph_replace "${root}" "__general_url__" "${general_url}"

        ph_replace "${root}" "__IDEAS_URL__" "${ideas_url}"
        ph_replace "${root}" "__ideas_url__" "${ideas_url}"

        ph_replace "${root}" "__POLLS_URL__" "${polls_url}"
        ph_replace "${root}" "__polls_url__" "${polls_url}"

        ph_replace "${root}" "__QA_URL__" "${qa_url}"
        ph_replace "${root}" "__qa_url__" "${qa_url}"

        ph_replace "${root}" "__SHOW_AND_TELL_URL__" "${show_and_tell_url}"
        ph_replace "${root}" "__show_and_tell_url__" "${show_and_tell_url}"

        if [[ -f "${root}/SECURITY.md" ]]; then
            security_url="$(gh_blob_url "${repo_url}" "${branch}" "SECURITY.md")"
        else
            security_url="${repo_url}/security"
        fi

        ph_replace "${root}" "__SECURITY_URL__" "${security_url}"
        ph_replace "${root}" "__security_url__" "${security_url}"

        if [[ -f "${root}/.github/SUPPORT.md" ]]; then
            support_url="$(gh_blob_url "${repo_url}" "${branch}" ".github/SUPPORT.md")"
        elif [[ -f "${root}/SUPPORT.md" ]]; then
            support_url="$(gh_blob_url "${repo_url}" "${branch}" "SUPPORT.md")"
        else
            support_url="${discussions_url}"
        fi

        ph_replace "${root}" "__SUPPORT_URL__" "${support_url}"
        ph_replace "${root}" "__support_url__" "${support_url}"

        if [[ -f "${root}/README.md" ]]; then
            readme_url="$(gh_blob_url "${repo_url}" "${branch}" "README.md")"
            ph_replace "${root}" "__README_URL__" "${readme_url}"
            ph_replace "${root}" "__readme_url__" "${readme_url}"
        fi

        if [[ -f "${root}/CONTRIBUTING.md" ]]; then
            contributing_url="$(gh_blob_url "${repo_url}" "${branch}" "CONTRIBUTING.md")"
        elif [[ -f "${root}/.github/CONTRIBUTING.md" ]]; then
            contributing_url="$(gh_blob_url "${repo_url}" "${branch}" ".github/CONTRIBUTING.md")"
        fi

        [[ -n "${contributing_url}" ]] && ph_replace "${root}" "__CONTRIBUTING_URL__" "${contributing_url}"
        [[ -n "${contributing_url}" ]] && ph_replace "${root}" "__contributing_url__" "${contributing_url}"

        if [[ -f "${root}/CODE_OF_CONDUCT.md" ]]; then
            coc_url="$(gh_blob_url "${repo_url}" "${branch}" "CODE_OF_CONDUCT.md")"
        elif [[ -f "${root}/.github/CODE_OF_CONDUCT.md" ]]; then
            coc_url="$(gh_blob_url "${repo_url}" "${branch}" ".github/CODE_OF_CONDUCT.md")"
        fi

        [[ -n "${coc_url}" ]] && ph_replace "${root}" "__CODE_OF_CONDUCT_URL__" "${coc_url}"
        [[ -n "${coc_url}" ]] && ph_replace "${root}" "__code_of_conduct_url__" "${coc_url}"

        if [[ -f "${root}/CHANGELOG.md" ]]; then
            changelog_url="$(gh_blob_url "${repo_url}" "${branch}" "CHANGELOG.md")"
            ph_replace "${root}" "__CHANGELOG_URL__" "${changelog_url}"
            ph_replace "${root}" "__changelog_url__" "${changelog_url}"
        fi
        if [[ -f "${root}/.github/PULL_REQUEST_TEMPLATE.md" ]]; then
            pr_tmpl_url="$(gh_blob_url "${repo_url}" "${branch}" ".github/PULL_REQUEST_TEMPLATE.md")"
        fi

        [[ -n "${pr_tmpl_url}" ]] && ph_replace "${root}" "__PULL_REQUEST_TEMPLATE_URL__" "${pr_tmpl_url}"
        [[ -n "${pr_tmpl_url}" ]] && ph_replace "${root}" "__pull_request_template_url__" "${pr_tmpl_url}"

        if [[ -d "${root}/.github/ISSUE_TEMPLATE" ]]; then
            issue_templates_url="$(gh_tree_url "${repo_url}" "${branch}" ".github/ISSUE_TEMPLATE")"
            ph_replace "${root}" "__ISSUE_TEMPLATES_URL__" "${issue_templates_url}"
            ph_replace "${root}" "__issue_templates_url__" "${issue_templates_url}"
        fi

        ph_replace "${root}" "__BUG_REPORT_URL__" "${new_issue_url}"
        ph_replace "${root}" "__bug_report_url__" "${new_issue_url}"
        ph_replace "${root}" "__FEATURE_REQUEST_URL__" "${new_issue_url}"
        ph_replace "${root}" "__feature_request_url__" "${new_issue_url}"

    fi

}
install () {

    local github_base=""
    local alias_name=""
    local gh_user=""
    local gh_repo=""
    local proj_name=""
    local branch=""
    local discord_url=""
    local docs_url=""
    local site_url=""

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -h|--help)
                usage
                return 0
            ;;
            -y|--yes)
                YES_ENV=1
                shift || true
            ;;
            -a|--alias)
                shift || true
                alias_name="${1:-}"
                [[ -n "${alias_name}" ]] || die "Missing alias value" 2
                shift || true
            ;;
            --alias=*)
                alias_name="${1#*=}"
                [[ -n "${alias_name}" ]] || die "Missing alias value" 2
                shift || true
            ;;
            --user)
                shift || true
                gh_user="${1:-}"
                [[ -n "${gh_user}" ]] || die "Missing user value" 2
                shift || true
            ;;
            --user=*)
                gh_user="${1#*=}"
                [[ -n "${gh_user}" ]] || die "Missing user value" 2
                shift || true
            ;;
            --repo)
                shift || true
                gh_repo="${1:-}"
                [[ -n "${gh_repo}" ]] || die "Missing repo value" 2
                shift || true
            ;;
            --repo=*)
                gh_repo="${1#*=}"
                [[ -n "${gh_repo}" ]] || die "Missing repo value" 2
                shift || true
            ;;
            --name)
                shift || true
                proj_name="${1:-}"
                [[ -n "${proj_name}" ]] || die "Missing name value" 2
                shift || true
            ;;
            --name=*)
                proj_name="${1#*=}"
                [[ -n "${proj_name}" ]] || die "Missing name value" 2
                shift || true
            ;;
            --branch)
                shift || true
                branch="${1:-}"
                [[ -n "${branch}" ]] || die "Missing branch value" 2
                shift || true
            ;;
            --branch=*)
                branch="${1#*=}"
                [[ -n "${branch}" ]] || die "Missing branch value" 2
                shift || true
            ;;
            --github-base)
                shift || true
                github_base="${1:-}"
                [[ -n "${github_base}" ]] || die "Missing github-base value" 2
                shift || true
            ;;
            --github-base=*)
                github_base="${1#*=}"
                [[ -n "${github_base}" ]] || die "Missing github-base value" 2
                shift || true
            ;;
            --discord)
                shift || true
                discord_url="${1:-}"
                [[ -n "${discord_url}" ]] || die "Missing discord value" 2
                shift || true
            ;;
            --discord=*)
                discord_url="${1#*=}"
                [[ -n "${discord_url}" ]] || die "Missing discord value" 2
                shift || true
            ;;
            --docs)
                shift || true
                docs_url="${1:-}"
                [[ -n "${docs_url}" ]] || die "Missing docs value" 2
                shift || true
            ;;
            --docs=*)
                docs_url="${1#*=}"
                [[ -n "${docs_url}" ]] || die "Missing docs value" 2
                shift || true
            ;;
            --site)
                shift || true
                site_url="${1:-}"
                [[ -n "${site_url}" ]] || die "Missing site value" 2
                shift || true
            ;;
            --site=*)
                site_url="${1#*=}"
                [[ -n "${site_url}" ]] || die "Missing site value" 2
                shift || true
            ;;
            --)
                shift || true
                break
            ;;
            -*)
                die "Unknown arg: ${1}" 2
            ;;
            *)
                die "Unknown arg: ${1}" 2
            ;;
        esac
    done

    local root="${ROOT_DIR}"
    [[ -n "${root}" ]] || die "ROOT_DIR is empty" 2

    [[ -n "${alias_name}" ]] || alias_name="vx"
    is_valid_alias "${alias_name}" || die "Invalid alias: ${alias_name}" 2

    github_base="${github_base%/}"
    [[ -n "${github_base}" ]] || github_base="https://github.com"
    [[ -n "${branch}" ]] || branch="$(detect_default_branch "${root}")"

    [[ -n "${gh_user}" ]] && gh_user="$(slugify "${gh_user}")"
    [[ -n "${gh_repo}" ]] && gh_repo="$(slugify "${gh_repo}")"
    [[ -n "${proj_name}" ]] && proj_name="$(slugify "${proj_name}")"

    [[ -z "${gh_repo}" && -n "${proj_name}" ]] && gh_repo="${proj_name}"
    [[ -z "${proj_name}" && -n "${gh_repo}" ]] && proj_name="${gh_repo}"

    local bin_path="$(install_launcher "${root}" "${alias_name}")"
    local rc="$(detect_rc)"

    ensure_path_once "${rc}" "${alias_name}"

    apply_placeholders \
        "${root}" \
        "${alias_name}" \
        "${gh_user}" \
        "${proj_name}" \
        "${gh_repo}" \
        "${branch}" \
        "${github_base}" \
        "${discord_url}" \
        "${docs_url}" \
        "${site_url}"

    printf '%s\n' \
        "OK: installed ${bin_path}" \
        "OK: updated ${rc}" \
        "Reload: source \"${rc}\"" \
        "Then: ${alias_name} --help"

}

install "$@"

# --------------------------
# ------ placeholders ------
# --------------------------
#
# __ALIAS__
# __NAME__
# __USER__
# __REPO__
# __BRANCH__
# __SITE_URL__
# __DOCS_URL__
# __DISCORD_URL__
# __REPO_URL__
# __ISSUES_URL__
# __NEW_ISSUE_URL__
# __BUG_REPORT_URL__
# __FEATURE_REQUEST_URL__
# __DISCUSSIONS_URL__
# __COMMUNITY_URL__
# __CATEGORIES_URL__
# __ANNOUNCEMENTS_URL__
# __GENERAL_URL__
# __IDEAS_URL__
# __POLLS_URL__
# __QA_URL__
# __SHOW_AND_TELL_URL__
# __SUPPORT_URL__
# __SECURITY_URL__
# __README_URL__
# __CONTRIBUTING_URL__
# __CODE_OF_CONDUCT_URL__
# __CHANGELOG_URL__
# __PULL_REQUEST_TEMPLATE_URL__
# __ISSUE_TEMPLATES_URL__
#
# --------------------------
