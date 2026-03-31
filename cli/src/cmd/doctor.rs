use colored::Colorize;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn home_dir() -> PathBuf {
    std::env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
}

fn zsh_env_dir() -> PathBuf {
    std::env::var("ZSH_ENV_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| home_dir().join(".zsh_env"))
}

/// Read ZSH_ENV_VERSION from core/ui.zsh
fn read_version() -> String {
    let ui_path = zsh_env_dir().join("core").join("ui.zsh");
    if let Ok(content) = fs::read_to_string(&ui_path) {
        for line in content.lines() {
            if let Some(rest) = line.strip_prefix("export ZSH_ENV_VERSION=\"") {
                if let Some(ver) = rest.strip_suffix('"') {
                    return ver.to_string();
                }
            }
        }
    }
    "unknown".to_string()
}

fn print_header(title: &str) {
    let version = read_version();
    let inner = format!(" {} {} ", title, version.dimmed());
    // The box width accommodates the title + version + padding
    let width = title.len() + version.len() + 3;
    let border = "─".repeat(width);
    println!("┌{}┐", border);
    println!("│{}│", inner);
    println!("└{}┘", border);
}

fn print_section(label: &str, content: &str) {
    print!("{:<14} {}\n", label.bold(), content);
}

fn print_separator(width: usize) {
    println!("{}", "─".repeat(width));
}

fn command_exists(name: &str) -> bool {
    Command::new("which")
        .arg(name)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn get_command_output(name: &str, args: &[&str]) -> Option<String> {
    Command::new(name)
        .args(args)
        .stderr(std::process::Stdio::null())
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                String::from_utf8(o.stdout).ok()
            } else {
                None
            }
        })
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

fn ok_indicator(name: &str) -> String {
    format!("{} {}", name, "✓".green())
}

fn ok_indicator_version(name: &str, version: &str) -> String {
    format!("{} {}{}", name, "✓".green(), version.dimmed())
}

fn fail_indicator(name: &str) -> String {
    format!("{} {}", name, "✗".red())
}

fn skip_indicator(name: &str) -> String {
    format!("{} {}", name.dimmed(), "○".dimmed())
}

// ---------------------------------------------------------------------------
// Module config parsing
// ---------------------------------------------------------------------------

fn read_module_config() -> Vec<(String, bool)> {
    let config_path = zsh_env_dir().join("config.zsh");
    let mut modules = Vec::new();

    if let Ok(content) = fs::read_to_string(&config_path) {
        let known = [
            ("ZSH_ENV_MODULE_GITLAB", "GitLab"),
            ("ZSH_ENV_MODULE_DOCKER", "Docker"),
            ("ZSH_ENV_MODULE_MISE", "Mise"),
            ("ZSH_ENV_MODULE_NUSHELL", "Nushell"),
            ("ZSH_ENV_MODULE_KUBE", "Kube"),
        ];
        for (var, label) in &known {
            let enabled = content.lines().any(|line| {
                let trimmed = line.trim();
                trimmed == format!("{}=true", var)
                    || trimmed == format!("{}=\"true\"", var)
            });
            modules.push((label.to_string(), enabled));
        }
    }

    modules
}

// ---------------------------------------------------------------------------
// Version extraction for kubernetes tools
// ---------------------------------------------------------------------------

fn kubectl_version() -> Option<String> {
    get_command_output("kubectl", &["version", "--client", "-o", "yaml"])
        .and_then(|out| {
            out.lines()
                .find(|l| l.contains("gitVersion"))
                .and_then(|l| l.split_whitespace().last())
                .map(|v| {
                    let s = v.to_string();
                    if s.len() > 6 { s[..6].to_string() } else { s }
                })
        })
}

fn az_version() -> Option<String> {
    get_command_output("az", &["version"])
        .and_then(|out| {
            // Parse JSON-ish output for "azure-cli" key
            out.lines()
                .find(|l| l.contains("azure-cli"))
                .and_then(|l| {
                    l.split('"')
                        .nth(3)
                        .map(|v| {
                            let s = v.to_string();
                            if s.len() > 5 { s[..5].to_string() } else { s }
                        })
                })
        })
}

fn helm_version() -> Option<String> {
    get_command_output("helm", &["version", "--short"])
        .map(|out| {
            let v = out.split('+').next().unwrap_or(&out).to_string();
            if v.len() > 6 { v[..6].to_string() } else { v }
        })
}

fn mise_version() -> Option<String> {
    get_command_output("mise", &["--version"])
        .map(|out| {
            out.split_whitespace()
                .next()
                .unwrap_or(&out)
                .to_string()
        })
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

pub fn run() {
    let env_dir = zsh_env_dir();
    let home = home_dir();

    let mut issues: u32 = 0;
    let mut warnings: u32 = 0;

    print_header("ZSH_ENV Doctor");

    // ── Config files ──────────────────────────────────────────────────────
    let config_files: Vec<(&str, PathBuf)> = vec![
        ("rc.zsh", env_dir.join("rc.zsh")),
        ("aliases", env_dir.join("core").join("aliases.zsh")),
        ("variables", env_dir.join("core").join("variables.zsh")),
        ("loader", env_dir.join("core").join("loader.zsh")),
    ];

    let mut config_parts: Vec<String> = Vec::new();
    for (label, path) in &config_files {
        if path.exists() {
            config_parts.push(ok_indicator(label));
        } else {
            config_parts.push(fail_indicator(label));
            issues += 1;
        }
    }
    print_section("Config", &config_parts.join("  "));

    // ── .zshrc integration ────────────────────────────────────────────────
    let zshrc_path = home.join(".zshrc");
    let zshrc_ok = fs::read_to_string(&zshrc_path)
        .map(|content| content.contains("ZSH_ENV_DIR"))
        .unwrap_or(false);

    if zshrc_ok {
        print_section("Integration", &ok_indicator(".zshrc"));
    } else {
        print_section("Integration", &fail_indicator(".zshrc"));
        issues += 1;
    }

    println!();

    // ── Required tools ────────────────────────────────────────────────────
    let required = ["git", "curl", "jq"];
    let mut req_parts: Vec<String> = Vec::new();
    for dep in &required {
        if command_exists(dep) {
            req_parts.push(ok_indicator(dep));
        } else {
            req_parts.push(fail_indicator(dep));
            issues += 1;
        }
    }
    print_section("Requis", &req_parts.join("  "));

    // ── Recommended tools ─────────────────────────────────────────────────
    let recommended = ["starship", "zoxide", "fzf", "eza", "bat", "sops", "age"];
    let mut rec_parts: Vec<String> = Vec::new();
    for dep in &recommended {
        if command_exists(dep) {
            rec_parts.push(ok_indicator(dep));
        } else {
            rec_parts.push(skip_indicator(dep));
            warnings += 1;
        }
    }
    print_section("Recommandes", &rec_parts.join("  "));

    // ── Kubernetes tools ──────────────────────────────────────────────────
    let kube_tools: Vec<(&str, Option<fn() -> Option<String>>)> = vec![
        ("kubectl", Some(kubectl_version as fn() -> Option<String>)),
        ("kubelogin", None),
        ("az", Some(az_version as fn() -> Option<String>)),
        ("helm", Some(helm_version as fn() -> Option<String>)),
    ];

    let mut kube_parts: Vec<String> = Vec::new();
    for (dep, version_fn) in &kube_tools {
        if command_exists(dep) {
            let ver = version_fn.and_then(|f| f());
            match ver {
                Some(v) => kube_parts.push(ok_indicator_version(dep, &v)),
                None => kube_parts.push(ok_indicator(dep)),
            }
        } else {
            kube_parts.push(skip_indicator(dep));
        }
    }
    print_section("Kubernetes", &kube_parts.join("  "));

    println!();

    // ── Modules ───────────────────────────────────────────────────────────
    let modules = read_module_config();
    let mut mod_parts: Vec<String> = Vec::new();
    for (label, enabled) in &modules {
        if *enabled {
            mod_parts.push(ok_indicator(label));
        } else {
            mod_parts.push(skip_indicator(label));
        }
    }
    if !mod_parts.is_empty() {
        print_section("Modules", &mod_parts.join("  "));
    }

    // ── Mise details ──────────────────────────────────────────────────────
    let mise_enabled = modules.iter().any(|(l, e)| l == "Mise" && *e);
    if mise_enabled {
        if command_exists("mise") {
            let ver = mise_version().unwrap_or_default();
            let mut mise_info = ok_indicator_version("mise", &ver);

            // Show active runtimes
            if let Some(node_ver) = get_command_output("mise", &["current", "node"]) {
                mise_info.push_str(&format!("  node:{}", node_ver.cyan()));
            }
            if let Some(java_ver) = get_command_output("mise", &["current", "java"]) {
                mise_info.push_str(&format!("  java:{}", java_ver.cyan()));
            }

            print_section("Mise", &mise_info);
        } else {
            let mise_info = format!(
                "mise {} {}",
                "○".yellow(),
                "(non installe)".dimmed()
            );
            print_section("Mise", &mise_info);
            warnings += 1;
        }
    }

    // ── SOPS/Age ──────────────────────────────────────────────────────────
    if command_exists("sops") && command_exists("age") {
        let age_key_file = home
            .join(".config")
            .join("sops")
            .join("age")
            .join("keys.txt");

        let sops_info = if age_key_file.exists() {
            let mut info = format!("cle {}  ", "✓".green());
            if let Ok(content) = fs::read_to_string(&age_key_file) {
                if let Some(pub_line) = content.lines().find(|l| l.contains("public key:")) {
                    if let Some(key) = pub_line.split_whitespace().last() {
                        let truncated = if key.len() > 16 {
                            format!("{}...", &key[..16])
                        } else {
                            key.to_string()
                        };
                        info.push_str(&truncated.dimmed().to_string());
                    }
                }
            }
            info
        } else {
            warnings += 1;
            format!(
                "cle {} {}",
                "○".yellow(),
                "(age-keygen -o ~/.config/sops/age/keys.txt)".dimmed()
            )
        };
        print_section("SOPS/Age", &sops_info);
    }

    // ── SSL/TLS ───────────────────────────────────────────────────────────
    let ssl_bundle = home.join(".ssl").join("ca-bundle.pem");
    let ssl_info = if ssl_bundle.exists() {
        let mut info = format!("bundle {}  ", "✓".green());
        if let Ok(content) = fs::read_to_string(&ssl_bundle) {
            let cert_count = content.matches("BEGIN CERTIFICATE").count();
            let enterprise_count = content.matches("Enterprise CA:").count();
            info.push_str(
                &format!("{} CAs ({} entreprise)", cert_count, enterprise_count)
                    .dimmed()
                    .to_string(),
            );
        }
        info
    } else {
        warnings += 1;
        format!(
            "bundle {} {}",
            "○".yellow(),
            "(zsh-env-ssl-setup)".dimmed()
        )
    };
    print_section("SSL/TLS", &ssl_info);

    println!();

    // ── Summary ───────────────────────────────────────────────────────────
    print_separator(44);
    if issues == 0 && warnings == 0 {
        println!("{}", "✓ Tout est OK".green());
    } else if issues == 0 {
        println!(
            "{} {}",
            "✓ OK".green(),
            format!("({} avertissement(s))", warnings).dimmed()
        );
    } else {
        println!(
            "{}, {}",
            format!("✗ {} erreur(s)", issues).red(),
            format!("{} avertissement(s)", warnings).yellow()
        );
        println!("{}", "Lancez ~/.zsh_env/install.sh pour corriger".dimmed());
    }
}
