#!/usr/bin/env bash

cmd_ci_help () {

    info_ln "CI :\n"

    printf '    %s\n' \
        "ci-stable           CI stable pipeline (check + test)" \
        "ci-nightly          CI nightly pipeline (check + test)" \
        "ci-msrv             CI msrv pipeline (check + test)" \
        "" \
        "ci-doc              CI docs pipeline (check-doc + test-doc)" \
        "ci-fmt              CI format pipeline (fmt-check)" \
        "ci-lint             CI lint pipeline (audit + taplo + prettier + spellcheck)" \
        "" \
        "ci-clippy           CI clippy pipeline (cargo-clippy)" \
        "ci-audit            CI audit pipeline (cargo-audit/deny)" \
        "ci-vet              CI vet feature-matrix pipeline (cargo-vet)" \
        "ci-hack             CI hack feature-matrix pipeline (cargo-hack)" \
        "ci-udeps            CI udeps feature-matrix pipeline (cargo-udeps)" \
        "ci-bloat            CI bloat feature-matrix pipeline (cargo-bloat)" \
        "" \
        "ci-fuzz             CI fuzz pipeline (runs targets with timeout & corpus)" \
        "ci-sanitizer        CI sanitizer pipeline" \
        "ci-miri             CI miri pipeline" \
        "" \
        "ci-semver           CI Semver pipeline (check semver)" \
        "ci-coverage         CI coverage pipeline (llvm-cov)" \
        "" \
        "ci-publish          CI publish gate then publish (full checks + publish)" \
        "ci-local            Run a pipline simulation ( full previous ci-xxx features )" \
        ''

}

cmd_ci_stable () {

    cmd_ensure

    info_ln "Check ...\n"
    cmd_check "$@"

    info_ln "Test ...\n"
    cmd_test "$@"

    cmd_clean_cache
    success_ln "CI Stable Succeeded.\n"

}
cmd_ci_nightly () {

    cmd_ensure

    info_ln "Check Nightly ...\n"
    cmd_check --nightly "$@"

    info_ln "Test Nightly ...\n"
    cmd_test --nightly "$@"

    cmd_clean_cache
    success_ln "CI Nightly Succeeded.\n"

}
cmd_ci_msrv () {

    cmd_ensure

    info_ln "Check Msrv ...\n"
    cmd_check --msrv "$@"

    info_ln "Test Msrv ...\n"
    cmd_test --msrv "$@"

    cmd_clean_cache
    success_ln "CI Msrv Succeeded.\n"

}

cmd_ci_doc () {

    cmd_ensure

    info_ln "Check Doc ...\n"
    cmd_check_doc "$@"

    info_ln "Test Doc ...\n"
    cmd_test_doc "$@"

    cmd_clean_cache
    success_ln "CI Doc Succeeded.\n"

}
cmd_ci_fmt () {

    cmd_ensure

    info_ln "Format ...\n"
    cmd_fmt_check "$@"

    cmd_clean_cache
    success_ln "CI Format Succeeded.\n"

}
cmd_ci_lint () {

    cmd_ensure

    info_ln "Taplo ...\n"
    cmd_taplo_check "$@"

    info_ln "Prettier ...\n"
    cmd_prettier_check "$@"

    info_ln "Spellcheck ...\n"
    cmd_spell_check "$@"

    cmd_clean_cache
    success_ln "CI Lint Succeeded.\n"

}

cmd_ci_clippy () {

    cmd_ensure

    info_ln "Clippy ...\n"
    cmd_clippy "$@"

    cmd_clean_cache
    success_ln "CI Clippy Succeeded.\n"

}
cmd_ci_audit () {

    cmd_ensure

    info_ln "Audit ...\n"
    cmd_audit_check "$@"

    cmd_clean_cache
    success_ln "CI Audit Succeeded.\n"

}
cmd_ci_vet () {

    cmd_ensure

    info_ln "Vet ...\n"
    cmd_vet_check "$@"

    cmd_clean_cache
    success_ln "CI Vet Succeeded.\n"

}
cmd_ci_hack () {

    cmd_ensure

    info_ln "Hack ...\n"
    cmd_hack "$@"

    cmd_clean_cache
    success_ln "CI Hack Succeeded.\n"

}
cmd_ci_udeps () {

    cmd_ensure

    info_ln "Udeps ...\n"
    cmd_udeps "$@"

    cmd_clean_cache
    success_ln "CI Udeps Succeeded.\n"

}
cmd_ci_bloat () {

    cmd_ensure

    info_ln "Bloat ...\n"
    cmd_bloat "$@"

    cmd_clean_cache
    success_ln "CI Bloat Succeeded.\n"

}

cmd_ci_fuzz () {

    cmd_ensure

    info_ln "Fuzz ...\n"
    cmd_fuzz "$@"

    cmd_clean_cache
    success_ln "CI Fuzz Succeeded.\n"

}
cmd_ci_sanitizer () {

    cmd_ensure

    info_ln "Sanitizer ...\n"
    cmd_sanitizer "$@"

    cmd_clean_cache
    success_ln "CI Sanitizer Succeeded.\n"

}
cmd_ci_miri () {

    cmd_ensure

    info_ln "Miri ...\n"
    cmd_miri "$@"

    cmd_clean_cache
    success_ln "CI Miri Succeeded.\n"

}

cmd_ci_semver () {

    cmd_ensure

    info_ln "Semver ...\n"
    cmd_semver "$@"

    cmd_clean_cache
    success_ln "CI Semver Succeeded.\n"

}
cmd_ci_coverage () {

    cmd_ensure

    info_ln "Coverage ...\n"
    cmd_coverage --upload "$@"

    cmd_clean_cache
    success_ln "CI Coverage Succeeded.\n"

}

cmd_ci_publish () {

    cmd_ensure

    info_ln "Publish ...\n"
    cmd_publish "$@"

    cmd_clean_cache
    success_ln "CI Publish Succeeded.\n"

}
cmd_ci_local () {

    cmd_ensure

    info_ln "Check ...\n"
    cmd_check

    info_ln "Test ...\n"
    cmd_test

    info_ln "Check Nightly ...\n"
    cmd_check --nightly

    info_ln "Test Nightly ...\n"
    cmd_test --nightly

    info_ln "Check Msrv ...\n"
    cmd_check --msrv

    info_ln "Test Msrv ...\n"
    cmd_test --msrv

    info_ln "Check Doc ...\n"
    cmd_check_doc

    info_ln "Test Doc ...\n"
    cmd_test_doc

    info_ln "Format ...\n"
    cmd_fmt_check

    info_ln "Taplo ...\n"
    cmd_taplo_check

    info_ln "Prettier ...\n"
    cmd_prettier_check

    info_ln "Spellcheck ...\n"
    cmd_spell_check

    info_ln "Clippy ...\n"
    cmd_clippy

    info_ln "Audit ...\n"
    cmd_audit_check

    info_ln "Vet ...\n"
    cmd_vet_check

    info_ln "Hack ...\n"
    cmd_hack

    info_ln "Udeps ...\n"
    cmd_udeps

    info_ln "Bloat ...\n"
    cmd_bloat

    info_ln "Fuzz ...\n"
    cmd_fuzz

    info_ln "Sanitizer ...\n"
    cmd_sanitizer

    info_ln "Miri ...\n"
    cmd_miri

    info_ln "Semver ...\n"
    cmd_semver

    info_ln "Coverage ...\n"
    cmd_coverage

    cmd_clean_cache
    success_ln "CI Pipeline Succeeded.\n"

}
