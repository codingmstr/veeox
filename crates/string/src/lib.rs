//! Veeox String crate.
//!
//! Public String surface for the Veeox workspace.
//! # veeox-api

pub struct Str;

impl Str {
    #[must_use]
    pub const fn name() -> &'static str {
        "veeox-string::Str"
    }
}
