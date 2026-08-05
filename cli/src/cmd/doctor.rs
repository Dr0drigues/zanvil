use crate::config::scan_module_metas;
use colored::Colorize;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn home_dir() -> PathBuf {
    std::env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
}

fn zanvil_dir() -> PathBuf {
    std::env::var("ZANVIL_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| home_dir().join(".zanvil"))
}

/// Read ZANVIL_VERSION from core/ui.zsh
fn read_version() -> String {
    let ui_path = zanvil_dir().join("core").join("ui.zsh");
    if let Ok(content) = fs::read_to_string(&ui_path) {
        for line in content.lines() {
            if let Some(rest) = line.strip_prefix("export ZANVIL_VERSION=\"") {
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

/// Cherche `zanvil` dans le PATH, et rend le premier chemin trouve.
///
/// On ne se contente pas de `current_exe()` : la question n'est pas « ou suis-je »
/// mais « qui repondra a une delegation zsh », et c'est le PATH qui en decide. Un
/// binaire lance par son chemin complet peut parfaitement ne pas etre celui que
/// `command -v zanvil` trouvera.
fn which_zanvil() -> Option<String> {
    let path = std::env::var_os("PATH")?;
    std::env::split_paths(&path)
        .map(|dir| dir.join("zanvil"))
        .find(|candidate| candidate.is_file())
        .map(|p| p.display().to_string())
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


// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

pub fn run() {
    let env_dir = zanvil_dir();
    let home = home_dir();

    let mut issues: u32 = 0;
    let mut warnings: u32 = 0;

    print_header("Zanvil Doctor");

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
        .map(|content| content.contains("ZANVIL_DIR"))
        .unwrap_or(false);

    if zshrc_ok {
        print_section("Integration", &ok_indicator(".zshrc"));
    } else {
        print_section("Integration", &fail_indicator(".zshrc"));
        issues += 1;
    }

    // ── Binaire ───────────────────────────────────────────────────────────
    // Une delegation zsh retombe sur son repli quand ce binaire manque du PATH, et
    // elle le fait silencieusement : ~/.local/bin a porte zsh-env-cli v3.0.0 pendant
    // quatre mois apres le renommage de la v4.0.0, sans que rien ne le signale.
    // Doctor est le seul endroit qui puisse le dire.
    match which_zanvil() {
        Some(path) => {
            let running = std::env::current_exe()
                .map(|p| p.display().to_string())
                .unwrap_or_default();
            if running == path {
                print_section("Binaire", &format!("{}  {}", "✓".green(), path.dimmed()));
            } else {
                // Un autre zanvil est premier dans le PATH : c'est lui qui repondra
                // aux delegations, pas celui qu'on vient de lancer.
                print_section(
                    "Binaire",
                    &format!(
                        "{}  {} {}",
                        "⚠".yellow(),
                        path.dimmed(),
                        "(repond aux delegations)".dimmed()
                    ),
                );
            }
        }
        None => {
            issues += 1;
            print_section(
                "Binaire",
                &format!(
                    "{}  absent du PATH — les commandes zsh tombent sur leur repli",
                    "✗".red()
                ),
            );
            println!(
                "               {}",
                format!(
                    "cd {}/cli && cargo build --release && cp target/release/zanvil ~/.local/bin/",
                    zanvil_dir().display()
                )
                .dimmed()
            );
        }
    }

    // ── Réglages hérités de l'ancien nom ──────────────────────────────────
    // Le renommage `zsh_env` → `zanvil` de la v4.0.0 a laissé deux choses derrière lui.
    // Le binaire, traité juste au-dessus. Et les variables d'environnement : la migration
    // réécrit `.zshrc` et `config.zsh`, pas `env.d/*.zsh`, qui est pourtant l'endroit que
    // la convention désigne pour elles.
    //
    // Sur la machine où ce contrôle a été écrit, quatre réglages étaient posés et ignorés
    // — l'URL Elasticsearch, celle du Nexus, un timeout et un TTL de cache. Aucun message,
    // aucune trace : la valeur par défaut s'appliquait et rien ne disait qu'un choix avait
    // été écrasé.
    //
    // Le contrôle ne devine rien : il lit les noms `ZANVIL_*` que le code consulte
    // vraiment, puis regarde si l'ancien équivalent traîne dans l'environnement. Un nom
    // que le projet a abandonné ne produit donc aucun bruit.
    let stale = stale_settings();
    if stale.is_empty() {
        print_section("Reglages", &ok_indicator("aucun nom herite"));
    } else {
        print_section(
            "Reglages",
            &format!(
                "{}  {}",
                "⚠".yellow(),
                format!("{} reglage(s) pose(s) sous l'ancien nom, donc ignore(s)", stale.len())
                    .yellow()
            ),
        );
        for (old, new) in &stale {
            println!("               {} → {}", old.dimmed(), new.bold());
        }
        println!(
            "               {}",
            "renommez-les dans env.d/*.zsh : le code ne lit plus que la forme ZANVIL_".dimmed()
        );
        warnings += stale.len() as u32;
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

    // ── Modules + Outils (depuis .module.toml) ───────────────────────────────
    let config_content = fs::read_to_string(env_dir.join("config.zsh")).unwrap_or_default();
    let metas = scan_module_metas(&env_dir);

    let mut mod_parts: Vec<String> = Vec::new();
    let mut tool_parts: Vec<String> = Vec::new();

    for meta in &metas {
        let guard_var = meta.guard.as_deref().unwrap_or("");
        let enabled = config_content.lines().any(|line| {
            let t = line.trim();
            t == format!("{}=true", guard_var) || t == format!("{}=\"true\"", guard_var)
        });

        let label = guard_var
            .strip_prefix("ZANVIL_MODULE_")
            .unwrap_or(guard_var);

        if let Some(binary) = meta.binary.as_deref() {
            // Tool module — section Outils
            if enabled {
                let bin = binary;
                if command_exists(bin) {
                    tool_parts.push(ok_indicator(label));
                } else {
                    let hint = meta.install.as_deref().unwrap_or(bin);
                    tool_parts.push(format!(
                        "{} {} {}",
                        label,
                        "✗".red(),
                        format!("({})", hint).dimmed()
                    ));
                    warnings += 1;
                }
            } else {
                tool_parts.push(skip_indicator(label));
            }
        } else {
            // Module sans binaire — section Modules
            if enabled {
                mod_parts.push(ok_indicator(label));
            } else {
                mod_parts.push(skip_indicator(label));
            }
        }
    }

    // Fallback : guards config.zsh sans .module.toml (ex: MISE, NUSHELL)
    let shown_guards: std::collections::HashSet<String> = metas
        .iter()
        .filter_map(|m| m.guard.clone())
        .collect();
    let config_modules = crate::config::parse_modules(&config_content);
    for m in &config_modules {
        let guard_var = format!("ZANVIL_MODULE_{}", m.name);
        if shown_guards.contains(&guard_var) {
            continue;
        }
        if m.enabled {
            mod_parts.push(ok_indicator(&m.name));
        } else {
            mod_parts.push(skip_indicator(&m.name));
        }
    }

    if !mod_parts.is_empty() {
        print_section("Modules", &mod_parts.join("  "));
    }
    if !tool_parts.is_empty() {
        print_section("Outils", &tool_parts.join("  "));
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
            "(zanvil-ssl-setup)".dimmed()
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
        println!("{}", "Lancez ~/.zanvil/install.sh pour corriger".dimmed());
    }
}

/// Les réglages posés sous l'ancien nom `ZSH_ENV_*` alors que le code lit `ZANVIL_*`.
///
/// Rend les paires (ancien, nouveau), triées et sans doublon.
///
/// **Le contrôle part du code, pas d'une liste.** Une liste en dur se périmerait au premier
/// réglage ajouté, et signalerait encore ceux que le projet a abandonnés — trois des sept
/// noms trouvés sur la machine de développement n'ont aucun équivalent lu, et les nommer
/// aurait été du bruit. Lire les `ZANVIL_*` que le code consulte vraiment évite les deux.
fn stale_settings() -> Vec<(String, String)> {
    let root = zanvil_dir();
    let mut names: std::collections::BTreeSet<String> = std::collections::BTreeSet::new();
    for dir in [root.join("core"), root.join("modules")] {
        collect_zanvil_names(&dir, &mut names);
    }

    names
        .into_iter()
        .filter_map(|new| {
            let suffix = new.strip_prefix("ZANVIL_")?;
            let old = format!("ZSH_ENV_{suffix}");
            // Une variable vide compte comme absente : c'est ce que fait `${X:-…}`, donc
            // un `export ZSH_ENV_X=""` n'écrase aucun choix.
            std::env::var(&old)
                .ok()
                .filter(|value| !value.is_empty())
                .map(|_| (old, new))
        })
        .collect()
}

/// Accumule les identifiants `ZANVIL_*` que les fichiers zsh d'un répertoire mentionnent.
fn collect_zanvil_names(dir: &Path, out: &mut std::collections::BTreeSet<String>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_zanvil_names(&path, out);
            continue;
        }
        if path.extension().is_none_or(|ext| ext != "zsh") {
            continue;
        }
        let Ok(content) = fs::read_to_string(&path) else {
            continue;
        };
        for line in content.lines() {
            // Les commentaires sont ignorés : `migrate_zanvil.zsh` nomme volontairement
            // les deux formes pour expliquer ce qu'il traduit.
            if line.trim_start().starts_with('#') {
                continue;
            }
            let mut rest = line;
            while let Some(at) = rest.find("ZANVIL_") {
                let tail = &rest[at..];
                let end = tail
                    .find(|c: char| !c.is_ascii_uppercase() && !c.is_ascii_digit() && c != '_')
                    .unwrap_or(tail.len());
                let name = &tail[..end];
                // `ZANVIL_` seul, ou terminé par un souligné, n'est pas un identifiant.
                if name.len() > "ZANVIL_".len() && !name.ends_with('_') {
                    out.insert(name.to_string());
                }
                rest = &tail[end.max(1)..];
            }
        }
    }
}
