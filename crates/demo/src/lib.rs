//! Demo crate.

pub struct Demo;

impl Demo {
    #[must_use]
    pub const fn run() -> &'static str {
        "Hello World"
    }
}
