use criterion::{Criterion, black_box, criterion_group, criterion_main};
use demo::Demo;

fn bench_demo(c: &mut Criterion) {
    let mut g = c.benchmark_group("demo::bench");

    g.bench_function("Demo::run", |b| {
        b.iter(|| {
            black_box(Demo::run());
        });
    });

    g.finish();
}

criterion_group!(benches, bench_demo);
criterion_main!(benches);
