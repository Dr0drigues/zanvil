use colored::*;
use std::process::Command;
use std::time::Instant;

pub fn run(runs: u32) {
    super::print_header("ZSH_ENV Benchmark");
    println!();
    println!("{:<14} {}", "Runs".bold(), runs);
    println!();

    let mut times: Vec<f64> = Vec::with_capacity(runs as usize);

    for i in 1..=runs {
        let start = Instant::now();
        let _ = Command::new("zsh")
            .args(["-i", "-c", "exit"])
            .output();
        let elapsed = start.elapsed().as_secs_f64() * 1000.0;
        times.push(elapsed);

        let pct = (i as f32 / runs as f32 * 20.0) as usize;
        let bar: String = "█".repeat(pct);
        let empty: String = "░".repeat(20 - pct);
        print!(
            "\r  {}[{}{}]{} Run {}/{}: {:6.0} ms",
            "".dimmed(),
            bar,
            empty,
            "".normal(),
            i,
            runs,
            elapsed
        );
    }

    println!();
    println!();

    // Stats
    times.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let min = times[0];
    let max = times[times.len() - 1];
    let avg: f64 = times.iter().sum::<f64>() / times.len() as f64;
    let p95_idx = ((times.len() as f64 * 0.95).ceil() as usize).min(times.len()) - 1;
    let p95 = times[p95_idx];

    println!("{}", "────────────────────────────────────────────".dimmed());
    println!("  {:<12} {:>6.0} ms", "Min".dimmed(), min);
    println!("  {:<12} {:>6.0} ms", "Moyenne".bold(), avg);
    println!("  {:<12} {:>6.0} ms", "P95".yellow(), p95);
    println!("  {:<12} {:>6.0} ms", "Max".red(), max);
}
