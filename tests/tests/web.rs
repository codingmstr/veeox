use veeox::{Request, Response, Route, Server};

#[test]
fn web() {
    println!("{}", Request::name());
    println!("{}", Response::name());
    println!("{}", Route::name());
    println!("{}", Server::name());
}
