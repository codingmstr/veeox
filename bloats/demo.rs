#[cfg(feature = "bloat-demo")]
fn main() {
    std::hint::black_box(demo::Demo::run());
}

#[cfg(not(feature = "bloat-demo"))]
fn main() {
    eprintln!("enable: --features bloat-demo");
    std::process::exit(2);
}
