use veeox::{Request, Response, Route, Server};

fn main() {
    println!("{}", Request::name());
    println!("{}", Response::name());
    println!("{}", Route::name());
    println!("{}", Server::name());
}
