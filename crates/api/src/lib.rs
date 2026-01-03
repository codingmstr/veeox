//! Veeox API crate.
//!
//! Public API surface for the Veeox workspace.

pub struct Api;

impl Api {
    #[must_use]
    pub const fn name() -> &'static str {
        "veeox-api::Api"
    }
}
