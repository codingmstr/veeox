# Contributing to Veeox

Thanks for your help improving Veeox — we're happy to have you here.

No contribution is too small.

## Getting started

1. Fork the repository and clone it locally.
2. Install Rust (rustup recommended).
3. From the repository root:

```bash
vx ci-fast
```

Before opening a PR (recommended for non-trivial changes):

```bash
vx ci-local
```

## Workspace notes

This repository is a Cargo workspace containing multiple crates:

* `crates/web/` -> `veeox` (facade)
* `crates/api/` -> `veeox-api`
* `crates/string/` -> `veeox-string`

## Pull Requests

* Keep PRs focused (one change per PR if possible).
* Update tests/docs when it makes sense.
* Fill the PR template (Type + Scope + Checklist).

## Code of Conduct

See `CODE_OF_CONDUCT.md`.

## Security

Please do not open public issues for security reports. See `SECURITY.md`.

## Need help?

Use GitHub Discussions for questions and design discussions.
