## ✨ Summary

- Added automatic PR labeling based on changed paths
  (tests/benches/examples/docs/ci/cargo/security/release/tooling/fuzz/crates/\*).
- Added label sync workflow to keep repo labels consistent from a single `.github/labels.yml`
  source of truth.
- Added a polished PR template to standardize reviews and reduce review latency.

## 🏷️ Type

- [ ] bug
- [ ] enhancement
- [ ] refactor
- [ ] chore

## 🧭 Scope

- [ ] ci
- [ ] tests
- [ ] benches
- [ ] examples
- [ ] fuzz
- [ ] docs
- [ ] cargo
- [ ] security
- [ ] release
- [ ] tooling
- [ ] crates:\*\*\*

## 💥 Notes / Links

- Goal: "single source of truth" for repo hygiene (labels + automation) to match the philosophy.
- Expected impact:
  - Faster triage (labels applied automatically).
  - Cleaner label taxonomy (auto-sync from `.github/labels.yml`).
  - Consistent PR quality (template-driven).

## 🧾 Overview

This PR upgrades repo hygiene and review flow:

- PRs get auto-labeled based on changed paths.
- Labels are synced from a single `.github/labels.yml` source of truth.
- A clean PR template standardizes what reviewers need to see.
