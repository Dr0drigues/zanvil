use crate::config;
use colored::*;
use std::process::Command;

pub fn run(check_only: bool) {
    let zsh_env_dir = config::zsh_env_dir();

    println!(
        "{}",
        "╭──────────────────────────────────────────╮".cyan()
    );
    println!(
        "{}  {:<30}    {}",
        "│".cyan(),
        "ZSH_ENV Update",
        "│".cyan()
    );
    println!(
        "{}",
        "╰──────────────────────────────────────────╯".cyan()
    );
    println!();

    // Fetch latest
    print!("  Fetch origin...  ");
    let fetch = Command::new("git")
        .args(["fetch", "--quiet", "origin"])
        .current_dir(&zsh_env_dir)
        .output();

    match fetch {
        Ok(out) if out.status.success() => println!("{}", "✓".green()),
        _ => {
            println!("{}", "✗".red());
            eprintln!("  {} Impossible de contacter le remote", "✗".red());
            return;
        }
    }

    // Compare HEAD vs origin/main
    let local_sha = git_rev_parse(&zsh_env_dir, "HEAD");
    let remote_sha = git_rev_parse(&zsh_env_dir, "origin/main");

    if local_sha == remote_sha {
        println!("  {} Deja a jour", "✓".green());
        return;
    }

    // Count commits behind
    let behind = Command::new("git")
        .args(["rev-list", "--count", "HEAD..origin/main"])
        .current_dir(&zsh_env_dir)
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| "?".to_string());

    println!(
        "  {} {} commit(s) en retard",
        "ℹ".cyan(),
        behind.yellow()
    );

    // Show recent commits from remote
    let log = Command::new("git")
        .args([
            "log",
            "--oneline",
            "--no-decorate",
            "-n",
            "5",
            "HEAD..origin/main",
        ])
        .current_dir(&zsh_env_dir)
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .unwrap_or_default();

    if !log.is_empty() {
        println!();
        for line in log.lines() {
            println!("    {}", line.dimmed());
        }
        println!();
    }

    if check_only {
        println!(
            "  {} Lancez {} pour mettre a jour",
            "ℹ".cyan(),
            "zsh-env-cli update".bold()
        );
        return;
    }

    // Pull
    print!("  Pull...  ");
    let pull = Command::new("git")
        .args(["pull", "--quiet", "origin", "main"])
        .current_dir(&zsh_env_dir)
        .output();

    match pull {
        Ok(out) if out.status.success() => println!("{}", "✓".green()),
        Ok(out) => {
            println!("{}", "✗".red());
            let stderr = String::from_utf8_lossy(&out.stderr);
            eprintln!("  {}", stderr.dimmed());
            return;
        }
        Err(e) => {
            println!("{}", "✗".red());
            eprintln!("  {}", e);
            return;
        }
    }

    // Check if CLI source changed
    let cli_changed = Command::new("git")
        .args(["diff", "--name-only", &local_sha, "HEAD", "--", "cli/"])
        .current_dir(&zsh_env_dir)
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| !s.trim().is_empty())
        .unwrap_or(false);

    if cli_changed {
        println!();
        print!("  CLI source modifie, recompilation...  ");

        let build = Command::new("cargo")
            .args(["build", "--release", "--quiet"])
            .current_dir(zsh_env_dir.join("cli"))
            .output();

        match build {
            Ok(out) if out.status.success() => {
                println!("{}", "✓".green());

                // Install binary
                let src = zsh_env_dir.join("cli/target/release/zsh-env-cli");
                if let Some(path) = which_cli() {
                    if let Err(e) = std::fs::copy(&src, &path) {
                        println!(
                            "  {} Copie du binaire echouee: {}",
                            "⚠".yellow(),
                            e
                        );
                    } else {
                        println!("  {} Binaire installe: {}", "✓".green(), path.display());
                    }
                }
            }
            Ok(out) => {
                println!("{}", "✗".red());
                let stderr = String::from_utf8_lossy(&out.stderr);
                eprintln!("  {}", stderr.dimmed());
            }
            Err(e) => {
                println!("{}", "✗".red());
                eprintln!("  {}", e);
            }
        }
    }

    // Check for pending migrations
    let migrations_dir = zsh_env_dir.join("migrations");
    if migrations_dir.is_dir() {
        let state_file = zsh_env_dir.join(".migration_version");
        let current_ver: u32 = std::fs::read_to_string(&state_file)
            .ok()
            .and_then(|s| s.trim().parse().ok())
            .unwrap_or(0);

        let has_pending = std::fs::read_dir(&migrations_dir)
            .ok()
            .map(|entries| {
                entries.filter_map(|e| e.ok()).any(|entry| {
                    let name = entry.file_name().to_string_lossy().to_string();
                    name.split('_')
                        .next()
                        .and_then(|n| n.parse::<u32>().ok())
                        .map(|n| n > current_ver)
                        .unwrap_or(false)
                })
            })
            .unwrap_or(false);

        if has_pending {
            println!();
            println!(
                "  {} Migrations en attente — lancez {}",
                "⚠".yellow(),
                "zsh-env-migrate".bold()
            );
        }
    }

    println!();
    println!(
        "  {} Mise a jour terminee. Rechargez avec: {}",
        "✓".green(),
        "ss".bold()
    );
}

fn git_rev_parse(dir: &std::path::Path, rev: &str) -> String {
    Command::new("git")
        .args(["rev-parse", rev])
        .current_dir(dir)
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .unwrap_or_default()
}

fn which_cli() -> Option<std::path::PathBuf> {
    Command::new("which")
        .arg("zsh-env-cli")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| std::path::PathBuf::from(s.trim()))
        .filter(|p| p.exists())
}
