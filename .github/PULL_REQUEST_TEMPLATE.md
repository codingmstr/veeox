## ✨ Summary

-   Added automatic PR labeling based on changed paths
    (tests/benches/examples/docs/ci/cargo/security/release/tooling/fuzz/crates/\*).
-   Added label sync workflow to keep repo labels consistent from a single `.github/labels.yml`
    source of truth.
-   Added a polished PR template to standardize reviews and reduce review latency.

## 🧭 Scope

-   [x] ci
-   [x] tests
-   [x] benches
-   [x] examples
-   [x] fuzz
-   [x] docs
-   [x] cargo
-   [x] security
-   [x] release
-   [x] tooling
-   [x] crates
-   [x] crates:\*\*\*

## ✅ Checklist

-   [x] `vx doctor` is clean
-   [x] `vx ci-local` passed
-   [x] Tests added/updated (where applicable) — N/A (workflow + templates only)
-   [x] Docs/comments added/updated (where applicable) — PR template added
-   [x] Examples/benches updated (where applicable) — N/A
-   [x] Changelog updated (where applicable) — N/A
-   [x] No breaking changes (or clearly documented below)

## 💥 Notes / Links

-   Goal: "single source of truth" for repo hygiene (labels + automation) to match the vx
    philosophy.
-   Expected impact:
    -   Faster triage (labels applied automatically).
    -   Cleaner label taxonomy (auto-sync from `.github/labels.yml`).
    -   Consistent PR quality (template-driven).

## 🧾 Overview

This PR upgrades repo hygiene and review flow:

-   PRs get auto-labeled based on changed paths.
-   Labels are synced from a single `.github/labels.yml` source of truth.
-   A clean PR template standardizes what reviewers need to see.
