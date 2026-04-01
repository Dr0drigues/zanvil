use colored::*;
use ignore::WalkBuilder;
use regex::Regex;
use std::fs;

struct SecretPattern {
    label: &'static str,
    regex: &'static str,
}

const PATTERNS: &[SecretPattern] = &[
    SecretPattern {
        label: "AWS Access Key",
        regex: r"AKIA[0-9A-Z]{16}",
    },
    SecretPattern {
        label: "Private Key",
        regex: r"-----BEGIN (RSA|EC|OPENSSH|DSA|PGP) PRIVATE KEY-----",
    },
    SecretPattern {
        label: "GitHub Token",
        regex: r"gh[ps]_[A-Za-z0-9_]{36,}",
    },
    SecretPattern {
        label: "GitHub PAT",
        regex: r"github_pat_[A-Za-z0-9_]{82,}",
    },
    SecretPattern {
        label: "GitLab Token",
        regex: r"glpat-[A-Za-z0-9_\-]{20,}",
    },
    SecretPattern {
        label: "Generic Token",
        regex: r#"(token|api_key|apikey|secret_key|secretkey)\s*[:=]\s*['"][^'"]{8,}['"]"#,
    },
    SecretPattern {
        label: "Generic Password",
        regex: r#"(password|passwd|pwd)\s*[:=]\s*['"][^'"]{8,}['"]"#,
    },
    SecretPattern {
        label: "Azure Key",
        regex: r"(AccountKey|SharedAccessKey|SharedAccessKeyName)\s*=\s*[A-Za-z0-9+/=]{20,}",
    },
    SecretPattern {
        label: "Slack Token",
        regex: r"xox[bporas]-[0-9A-Za-z\-]{10,}",
    },
    SecretPattern {
        label: "JWT",
        regex: r"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}",
    },
    SecretPattern {
        label: "Connection String",
        regex: r#"(mongodb|postgres|mysql|redis)://[^\s'"]{10,}"#,
    },
];

struct Finding {
    file: String,
    line: u32,
    label: String,
    masked: String,
}

fn mask_value(val: &str) -> String {
    if val.len() <= 8 {
        "****".to_string()
    } else {
        format!("{}...{}", &val[..4], &val[val.len() - 4..])
    }
}

pub fn run(dir: &str, includes: &[String], excludes: &[String]) {
    println!(
        "{}",
        "╭──────────────────────────────────────────╮".cyan()
    );
    println!(
        "{}  {:<30}    {}",
        "│".cyan(),
        "Secrets Scan",
        "│".cyan()
    );
    println!(
        "{}",
        "╰──────────────────────────────────────────╯".cyan()
    );
    println!();
    println!("{:<14} {}", "Dossier".bold(), dir);
    println!("{:<14} {}", "Moteur".bold(), "Rust (ignore + regex)");
    if !includes.is_empty() {
        println!("{:<14} {}", "Include".bold(), includes.join(", "));
    }
    if !excludes.is_empty() {
        println!("{:<14} {}", "Exclude".bold(), excludes.join(", "));
    }
    println!();

    // Compile all patterns
    let compiled: Vec<(&str, Regex)> = PATTERNS
        .iter()
        .filter_map(|p| Regex::new(p.regex).ok().map(|r| (p.label, r)))
        .collect();

    // Build walker (respects .gitignore by default)
    let mut builder = WalkBuilder::new(dir);
    builder.hidden(false).git_ignore(true).git_global(true);

    // Default exclude patterns
    let default_excludes = [
        "*.min.js",
        "*.min.css",
        "*.map",
        "*.lock",
        "*.wasm",
        "*.png",
        "*.jpg",
        "*.gif",
        "*.ico",
        "*.pdf",
        "*.svg",
        "*.zip",
        "*.tar.gz",
        "package-lock.json",
        "yarn.lock",
    ];

    // Exclusions are handled via overrides below

    // Build glob overrides
    let mut overrides = ignore::overrides::OverrideBuilder::new(dir);
    for ex in &default_excludes {
        let _ = overrides.add(&format!("!{}", ex));
    }
    for ex in excludes {
        let _ = overrides.add(&format!("!{}", ex));
    }
    for inc in includes {
        let _ = overrides.add(inc);
    }
    if let Ok(ov) = overrides.build() {
        builder.overrides(ov);
    }

    let mut findings: Vec<Finding> = Vec::new();

    // Walk files
    for result in builder.build() {
        let entry = match result {
            Ok(e) => e,
            Err(_) => continue,
        };

        if !entry.file_type().map_or(false, |ft| ft.is_file()) {
            continue;
        }

        let path = entry.path();
        let content = match fs::read_to_string(path) {
            Ok(c) => c,
            Err(_) => continue, // Skip binary files
        };

        for (line_num, line) in content.lines().enumerate() {
            for (label, regex) in &compiled {
                if let Some(mat) = regex.find(line) {
                    let relpath = path
                        .strip_prefix(dir)
                        .unwrap_or(path)
                        .to_string_lossy()
                        .to_string();

                    findings.push(Finding {
                        file: relpath,
                        line: (line_num + 1) as u32,
                        label: label.to_string(),
                        masked: mask_value(mat.as_str()),
                    });
                }
            }
        }
    }

    // Dedup by file:line
    findings.sort_by(|a, b| (&a.file, a.line).cmp(&(&b.file, b.line)));
    findings.dedup_by(|a, b| a.file == b.file && a.line == b.line);

    // Display
    println!(
        "  {:<38} {:<16} {}",
        "Fichier".bold(),
        "Type".bold(),
        "Valeur".bold()
    );
    println!(
        "{}",
        "────────────────────────────────────────────────────────────────".dimmed()
    );

    for f in &findings {
        println!(
            "  {:<38} {:<16} {}",
            format!("{}:{}", f.file, f.line).yellow(),
            f.label.red(),
            f.masked.dimmed()
        );
    }

    println!();
    println!(
        "{}",
        "────────────────────────────────────────────────────────────────".dimmed()
    );
    if findings.is_empty() {
        println!("{} Aucun secret detecte", "✓".green());
    } else {
        println!(
            "{} {} secret(s) detecte(s)",
            "✗".red(),
            findings.len().to_string().red()
        );
        println!();
        println!(
            "{}",
            "⚠ Verifiez ces resultats — certains peuvent etre des faux positifs".yellow()
        );
    }
}

