use criterion::{black_box, criterion_group, criterion_main, Criterion};

use veeox::{Middleware, Request, Response, Route, Server};

fn bench_web(c: &mut Criterion) {
    let mut g = c.benchmark_group("veeox::bench_web");

    g.bench_function("Request::name", |b| {
        b.iter(|| {
            black_box(Request::name());
        });
    });

    g.bench_function("Response::name", |b| {
        b.iter(|| {
            black_box(Response::name());
        });
    });

    g.bench_function("Route::name", |b| {
        b.iter(|| {
            black_box(Route::name());
        });
    });

    g.bench_function("Middleware::name", |b| {
        b.iter(|| {
            black_box(Middleware::name());
        });
    });

    g.bench_function("Server::name", |b| {
        b.iter(|| {
            black_box(Server::name());
        });
    });

    g.finish();
}

criterion_group!(benches, bench_web);
criterion_main!(benches);
