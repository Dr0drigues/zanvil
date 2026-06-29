use colored::*;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

fn _zanvil_dir() -> PathBuf {
    PathBuf::from(
        std::env::var("ZANVIL_DIR")
            .unwrap_or_else(|_| format!("{}/.zanvil", std::env::var("HOME").unwrap_or_default())),
    )
}

fn home_dir() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_default())
}

fn get_perms(path: &Path) -> Option<u32> {
    if !path.exists() {
        return None;
    }
    let meta = fs::metadata(path).ok()?;
    Some(meta.permissions().mode() & 0o777)
}

fn format_perm_check(label: &str, path: &Path, expected: &[u32], issues: &mut u32) -> String {
    match get_perms(path) {
        Some(mode) => {
            if expected.contains(&mode) {
                format!("{} {}", label, "✓".green())
            } else {
                *issues += 1;
                format!("{} {}{}", label, "✗".red(), format!("{:o}", mode).dimmed())
            }
        }
        None => format!("{} {}", label, "−".dimmed()),
    }
}

fn section(label: &str, content: &str) {
    print!("{:<14} {}\n", label.bold(), content);
}

pub fn run() {
    let home = home_dir();
    let mut issues: u32 = 0;
    let mut warnings: u32 = 0;

    super::print_header("Zanvil Security Audit");
    println!();

    // --- SSH ---
    let ssh_dir = home.join(".ssh");
    let mut ssh_status = String::new();
    ssh_status.push_str(&format_perm_check("~/.ssh", &ssh_dir, &[0o700], &mut issues));
    ssh_status.push_str("  ");

    // Check SSH private keys
    if ssh_dir.exists() {
        if let Ok(entries) = fs::read_dir(&ssh_dir) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_string();
                if name.starts_with("id_") && !name.ends_with(".pub") {
                    ssh_status.push_str(&format_perm_check(
                        &name,
                        &entry.path(),
                        &[0o600, 0o400],
                        &mut issues,
                    ));
                    ssh_status.push_str("  ");
                }
            }
        }
    }
    section("SSH", &ssh_status);

    // --- Secrets files ---
    let secrets_files = vec![
        ("~/.secrets", home.join(".secrets")),
        ("~/.gitlab_secrets", home.join(".gitlab_secrets")),
        ("~/.netrc", home.join(".netrc")),
        ("~/.npmrc", home.join(".npmrc")),
    ];
    let mut secrets_status = String::new();
    for (label, path) in &secrets_files {
        if path.exists() {
            secrets_status.push_str(&format_perm_check(label, path, &[0o600, 0o400], &mut issues));
            secrets_status.push_str("  ");
        }
    }
    if !secrets_status.is_empty() {
        section("Secrets", &secrets_status);
    }

    // --- Kube ---
    let kube_dir = home.join(".kube");
    if kube_dir.exists() {
        let mut kube_status = String::new();
        kube_status.push_str(&format_perm_check("~/.kube", &kube_dir, &[0o700, 0o755], &mut warnings));
        kube_status.push_str("  ");

        let kube_config = kube_dir.join("config");
        if kube_config.exists() {
            kube_status.push_str(&format_perm_check("config", &kube_config, &[0o600, 0o644], &mut warnings));
            kube_status.push_str("  ");
        }

        // Check configs.d/
        let configs_d = kube_dir.join("configs.d");
        if configs_d.exists() {
            if let Ok(entries) = fs::read_dir(&configs_d) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.is_file() {
                        let name = entry.file_name().to_string_lossy().to_string();
                        kube_status.push_str(&format_perm_check(
                            &name,
                            &path,
                            &[0o600, 0o644],
                            &mut warnings,
                        ));
                        kube_status.push_str("  ");
                    }
                }
            }
        }
        section("Kubernetes", &kube_status);
    }

    // --- Git credentials ---
    let git_creds = home.join(".git-credentials");
    if git_creds.exists() {
        issues += 1;
        section(
            "Git",
            &format!(
                ".git-credentials {} {}",
                "✗".red(),
                "(fichier plaintext detecte)".dimmed()
            ),
        );
    } else {
        section("Git", &format!("credentials {}", "✓".green()));
    }

    // --- History files ---
    let history_files = vec![
        ("zsh_history", home.join(".zsh_history")),
        ("bash_history", home.join(".bash_history")),
    ];
    let mut hist_status = String::new();
    for (label, path) in &history_files {
        if path.exists() {
            hist_status.push_str(&format_perm_check(label, path, &[0o600], &mut warnings));
            hist_status.push_str("  ");
        }
    }
    if !hist_status.is_empty() {
        section("History", &hist_status);
    }

    // --- AWS ---
    let aws_creds = home.join(".aws").join("credentials");
    if aws_creds.exists() {
        section(
            "AWS",
            &format_perm_check("credentials", &aws_creds, &[0o600], &mut issues),
        );
    }

    // --- SOPS/Age ---
    let age_key = home.join(".config").join("sops").join("age").join("keys.txt");
    if age_key.exists() {
        section(
            "SOPS/Age",
            &format_perm_check("keys.txt", &age_key, &[0o600, 0o400], &mut issues),
        );
    }

    // --- Summary ---
    println!("{}", "────────────────────────────────────────────".dimmed());
    if issues == 0 && warnings == 0 {
        println!("{} Tout est OK", "✓".green());
    } else if issues == 0 {
        println!(
            "{} OK {}",
            "✓".green(),
            format!("({} avertissement(s))", warnings).dimmed()
        );
    } else {
        println!(
            "{} {} erreur(s), {} avertissement(s)",
            "✗".red(),
            issues,
            warnings
        );
    }
}
