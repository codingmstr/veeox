#!/usr/bin/env bash

cmd_notify_help () {

    info_ln "Notify :\n"

    printf '    %s\n' \
        "send-notify         send notification ( slack, telegram ), --token --retries: (default: 3)" \
        ''

}
cmd_send_notify () {

    ensure curl jq

    source <(parse "$@" -- \
        platform:str \
        token webhook chat \
        title status text url \
        strict:bool \
    )

    local platform="${platform:-}"
    [[ -n "${platform}" ]] || die "notify: missing --platform" 2

    local status="${status:-success}"
    local title="${title:-CI}"
    local url="${url:-}"

    if [[ -z "${text:-}" ]]; then
        local repo="${GITHUB_REPOSITORY:-local}"
        local ref="${GITHUB_REF_NAME:-${GITHUB_REF:-}}"
        local sha="${GITHUB_SHA:-}"
        [[ -n "${sha}" ]] && sha="${sha:0:7}"

        local run_url=""
        if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_RUN_ID:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
            run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
        fi

        url="${url:-${run_url}}"
        text="[$title] status=${status} repo=${repo} ref=${ref} sha=${sha}"
        [[ -n "${url}" ]] && text="${text} url=${url}"
    fi

    # Don’t leak secrets if VERBOSE is on
    local old_verbose="${VERBOSE_ENV:-0}"
    VERBOSE_ENV=0

    case "${platform}" in

        telegram)
            [[ -n "${token:-}" ]] || token="${TELEGRAM_TOKEN:-}"
            [[ -n "${chat:-}"  ]] || chat="${TELEGRAM_CHAT_ID:-}"

            if [[ -z "${token}" || -z "${chat}" ]]; then
                (( ${strict:-0} )) && die "notify: missing telegram token/chat" 2
                error "notify: skip telegram (missing token/chat)"
                VERBOSE_ENV="${old_verbose}"
                return 0
            fi

            run curl -fsS -X POST \
                "https://api.telegram.org/bot${token}/sendMessage" \
                -d "chat_id=${chat}" \
                --data-urlencode "text=${text}" \
                -d "disable_web_page_preview=true" \
                >/dev/null

        ;;

        slack)
            [[ -n "${webhook:-}" ]] || webhook="${SLACK_WEBHOOK_URL:-}"

            if [[ -z "${webhook}" ]]; then
                (( ${strict:-0} )) && die "notify: missing slack webhook" 2
                error "notify: skip slack (missing webhook)"
                VERBOSE_ENV="${old_verbose}"
                return 0
            fi

            local payload=""
            payload="$(jq -Rn --arg t "${text}" '{text:$t}')"

            run curl -fsS -X POST \
                -H "Content-Type: application/json" \
                --data "${payload}" \
                "${webhook}" \
                >/dev/null
        ;;

        *)
            VERBOSE_ENV="${old_verbose}"
            die "notify: unknown platform: ${platform}" 2
        ;;

    esac

    VERBOSE_ENV="${old_verbose}"
    success "notify: sent (${platform})"

}

# notify:
#     name: notify
#     runs-on: ubuntu-latest
#     needs: [stable, nightly, msrv, doc, lint, hack, cross, semver, fuzz, coverage, publish]
#     if: ${{ always() }}

#     steps:
#       - uses: actions/checkout@v6

#       - name: Notify admin
#         env:
#           # Results
#           R_STABLE:  ${{ needs.stable.result }}
#           R_NIGHTLY: ${{ needs.nightly.result }}
#           R_MSRV:    ${{ needs.msrv.result }}
#           R_DOC:     ${{ needs.doc.result }}
#           R_LINT:    ${{ needs.lint.result }}
#           R_HACK:    ${{ needs.hack.result }}
#           R_CROSS:   ${{ needs.cross.result }}
#           R_SEMVER:  ${{ needs.semver.result }}
#           R_FUZZ:    ${{ needs.fuzz.result }}
#           R_COV:     ${{ needs.coverage.result }}
#           R_PUB:     ${{ needs.publish.result }}

#           TELEGRAM_TOKEN:   ${{ secrets.TELEGRAM_TOKEN }}
#           TELEGRAM_CHAT_ID: ${{ secrets.TELEGRAM_CHAT_ID }}
#           SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}

#         run: |
#           set -euo pipefail

#           status="success"
#           for r in "${R_STABLE}" "${R_MSRV}" "${R_DOC}" "${R_LINT}" "${R_HACK}" "${R_CROSS}" "${R_SEMVER}" "${R_NIGHTLY}" "${R_FUZZ}" "${R_COV}" "${R_PUB}"; do
#               case "${r}" in
#                   failure|cancelled) status="failure"; break ;;
#               esac
#           done

#           bash ./scripts/run.sh notify \
#               --platform "telegram" \
#               --status "${status}" \
#               --title "CI" \
#               --text "CI finished: status=${status}"
