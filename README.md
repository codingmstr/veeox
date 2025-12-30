# veeox

A modern Rust ecosystem for building reliable, high-performance backend and web systems.

**veeox** is designed around small, focused crates with a clean facade crate (`veeox`) that
re-exports the core building blocks.

-   **Fast:** performance-first APIs with minimal overhead.
-   **Reliable:** Rust type system + ownership to reduce bugs.
-   **Scalable:** modular crates, clear boundaries, and production-grade practices.

Crates.io | MIT licensed | CI (coming soon)

Website | Guides | API Docs | Chat (coming soon)

---

## Overview

veeox is a workspace of crates that will evolve into a full backend stack. At a high level, it aims
to provide:

-   A web facade crate (`veeox`) exporting stable, ergonomic primitives.
-   Utility crates (strings, api contracts, config, env, logging, etc.).
-   Clean integration patterns with the wider Rust ecosystem (tokio, hyper, tracing, serde, memchr,
    ...).

### Workspace crates (current)

-   **veeox** (facade; located in `web/`)
-   **veeox-api** (contracts & shared API utilities)
-   **veeox-string** (string/text utilities)

> Status: early `0.1.x` — APIs may change.

---

## Example

Minimal usage showing the facade and re-exported types:

```toml
[dependencies]
veeox = "0.1.0"
```

```rust
use veeox::{Api, Str, Request, Response, Route, Server};

fn main () {

    println!("{}", Api::name());
    println!("{}", Str::name());

    println!("{}", Request::name());
    println!("{}", Response::name());
    println!("{}", Route::name());
    println!("{}", Server::name());

}
```

---

## Getting Help

-   Start with the repository README and crate documentation on docs.rs (once published).
-   If you have questions, open a GitHub Discussion (recommended) or an Issue.

---

## Contributing

🎈 Thanks for helping improve veeox!

See `CONTRIBUTING.md` for development setup and contribution guidelines.

---

## Roadmap (high-level)

-   Solidify the facade API surface (`Request`, `Response`, `Route`, `Server`, `Middleware`).
-   Expand `veeox-string` with fast, Unicode-aware text primitives.
-   Add ecosystem crates: `veeox-env`, `veeox-config`, `veeox-log`, `veeox-cache`, `veeox-db`, ...

---

## Supported Rust Versions (MSRV)

veeox targets stable Rust. During the early `0.1.x` phase, the MSRV may change as the project
evolves. Once the project stabilizes, we will adopt a rolling MSRV policy (like major Rust ecosystem
projects).

---

## License

This project is licensed under the **MIT license**. See `LICENSE`.

---

## Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in
veeox by you shall be licensed as MIT, without any additional terms or conditions.
