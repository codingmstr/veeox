# Contributing to veeox

Thanks for your help improving veeox — we're happy to have you here.

There are opportunities to contribute at any level. No contribution is too small.

## Getting started

1. Fork the repository and clone it locally.

2. Install stable Rust (rustup recommended).

3. From the repository root:

```bash
cargo fmt
cargo test --workspace
```

Optional but recommended:

```bash
cargo clippy --workspace --all-targets --all-features -D warnings
```

## Workspace notes

This repository is a Cargo workspace containing multiple crates:

-   `web/` -> crate `veeox` (facade)
-   `api/` -> crate `veeox-api`
-   `string/` -> crate `veeox-string`

## Pull Requests

-   Keep PRs focused (one change per PR if possible).
-   Add or update docs/tests when it makes sense.
-   Make sure formatting and tests pass:

    -   `cargo fmt`
    -   `cargo test --workspace`

## Code of Conduct

The veeox project adheres to the Rust Code of Conduct. See `CODE_OF_CONDUCT.md`.

## Need Help?

Open a GitHub Discussion for questions not covered by the docs.
