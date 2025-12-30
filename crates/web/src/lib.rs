pub use veeox_api::Api;
pub use veeox_string::Str;

pub struct Request;
pub struct Response;
pub struct Middleware;
pub struct Route;
pub struct Server;

impl Request {
    #[must_use]
    pub const fn name() -> &'static str {
        "veeox::Request"
    }
}

impl Response {
    #[must_use]
    pub const fn name() -> &'static str {
        "veeox::Response"
    }
}

impl Middleware {
    #[must_use]
    pub const fn name() -> &'static str {
        "veeox::Middleware"
    }
}

impl Route {
    #[must_use]
    pub const fn name() -> &'static str {
        "veeox::Route"
    }
}

impl Server {
    #[must_use]
    pub const fn name() -> &'static str {
        "veeox::Server"
    }
}
