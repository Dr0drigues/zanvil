use crate::config;
use clap::Subcommand;
use colored::*;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;

#[derive(Subcommand)]
pub enum SyncAction {
    /// Export configuration to JSON
    Export {
        /// Output file path
        #[arg(default_value = "sync.json")]
        output: String,
    },
    /// Import configuration from JSON
    Import {
        /// Input file path
        file: String,
    },
    /// Compare local config with exported file
    Diff {
        /// File to compare with
        file: String,
    },
}

#[derive(Serialize, Deserialize)]
struct SyncConfig {
    version: String,
    exported_at: String,
    modules: BTreeMap<String, bool>,
    theme: String,
    #[serde(default)]
    theme_light: String,
    #[serde(default)]
    theme_dark: String,
    #[serde(default)]
    plugins: Vec<String>,
    auto_update: AutoUpdateConfig,
}

#[derive(Serialize, Deserialize)]
struct AutoUpdateConfig {
    enabled: bool,
    frequency: u32,
    mode: String,
}

pub fn run(action: SyncAction) {
    match action {
        SyncAction::Export { output } => export(&output),
        SyncAction::Import { file } => import(&file),
        SyncAction::Diff { file } => diff(&file),
    }
}

fn export(output: &str) {
    crate::cmd::print_header("Zanvil Sync Export");

    let content = match config::read_config() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{} {}", "✗".red(), e);
            return;
        }
    };

    let modules = config::parse_modules(&content);
    let mut mod_map = BTreeMap::new();
    for m in &modules {
        mod_map.insert(m.name.clone(), m.enabled);
    }

    // Read current theme
    let theme_file = config::zanvil_dir().join(".current_theme");
    let theme = fs::read_to_string(&theme_file)
        .unwrap_or_else(|_| "default".to_string())
        .trim()
        .to_string();

    // Read theme light/dark
    let theme_light = extract_value(&content, "ZANVIL_THEME_LIGHT");
    let theme_dark = extract_value(&content, "ZANVIL_THEME_DARK");

    // Read auto-update settings
    let au_enabled = extract_value(&content, "ZANVIL_AUTO_UPDATE") == "true";
    let au_freq: u32 = extract_value(&content, "ZANVIL_UPDATE_FREQUENCY")
        .parse()
        .unwrap_or(7);
    let au_mode = extract_value(&content, "ZANVIL_UPDATE_MODE")
        .trim_matches('"')
        .to_string();

    // Version
    let ui_path = config::zanvil_dir().join("core/ui.zsh");
    let version = fs::read_to_string(&ui_path)
        .ok()
        .and_then(|c| {
            c.lines()
                .find(|l| l.contains("ZANVIL_VERSION="))
                .map(|l| {
                    l.split('=')
                        .nth(1)
                        .unwrap_or("unknown")
                        .trim_matches('"')
                        .to_string()
                })
        })
        .unwrap_or_else(|| "unknown".to_string());

    let sync = SyncConfig {
        version,
        exported_at: chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        modules: mod_map,
        theme,
        theme_light,
        theme_dark,
        // Les plugins etaient exportes comme un tableau vide en dur. Un poste qui en
        // declarait les perdait a la synchronisation, sans que rien ne le signale.
        plugins: config::parse_array(&content, "ZANVIL_PLUGINS"),
        auto_update: AutoUpdateConfig {
            enabled: au_enabled,
            frequency: au_freq,
            mode: if au_mode.is_empty() {
                "prompt".to_string()
            } else {
                au_mode
            },
        },
    };

    let output_path = if output.starts_with('/') {
        PathBuf::from(output)
    } else {
        config::zanvil_dir().join(output)
    };

    match serde_json::to_string_pretty(&sync) {
        Ok(json) => {
            if let Err(e) = fs::write(&output_path, &json) {
                eprintln!("{} Erreur: {}", "✗".red(), e);
            } else {
                println!("{} Config exportee: {}", "✓".green(), output_path.display());
                println!();
                // Le meme resume que le zsh imprimait : ce qui vient de partir dans le
                // fichier, en trois lignes, pour qu on n ait pas a l ouvrir.
                crate::cmd::print_section("Version", &sync.version);
                crate::cmd::print_section("Theme", &sync.theme);
                crate::cmd::print_section("Modules", &compact_modules(&sync.modules));
            }
        }
        Err(e) => eprintln!("{} Serialisation: {}", "✗".red(), e),
    }
}

/// Rend les modules sur une ligne, comme le resume du zsh les affichait.
fn compact_modules(modules: &BTreeMap<String, bool>) -> String {
    let inner: Vec<String> = modules
        .iter()
        .map(|(name, enabled)| format!("\"{}\":{}", name, enabled))
        .collect();
    format!("{{{}}}", inner.join(","))
}

fn import(file: &str) {
    crate::cmd::print_header("Zanvil Sync Import");
    crate::cmd::print_section("Source", file);
    println!();

    let content = match fs::read_to_string(file) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{} Impossible de lire {}: {}", "✗".red(), file, e);
            return;
        }
    };

    let sync: SyncConfig = match serde_json::from_str(&content) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("{} JSON invalide: {}", "✗".red(), e);
            return;
        }
    };

    let mut config_content = match config::read_config() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{} {}", "✗".red(), e);
            return;
        }
    };

    // Backup
    let backup_path = config::config_path().with_extension("zsh.pre-import");
    let _ = fs::copy(config::config_path(), &backup_path);
    println!("{} Backup: {}", "ℹ".cyan(), backup_path.display());

    // Apply modules
    for (name, enabled) in &sync.modules {
        match config::set_module(&config_content, name, *enabled) {
            Ok(new) => {
                config_content = new;
                println!("  {} ZANVIL_MODULE_{}={}", "✓".green(), name, enabled);
            }
            Err(_) => {
                println!("  {} ZANVIL_MODULE_{} (absent)", "−".dimmed(), name);
            }
        }
    }

    // Les cinq reglages que cet import ignorait, alors qu il annoncait « Config
    // importee » : les deux themes clair/sombre et les trois d auto-update. Un
    // utilisateur qui synchronisait deux machines croyait sa config alignee.
    //
    // Une valeur vide n est pas appliquee : le JSON porte `""` quand la machine
    // d origine n avait pas le reglage, et poser `CLE=` dans config.zsh donnerait a une
    // absence la forme d un choix.
    if !sync.theme_light.is_empty() {
        config_content = config::set_value(&config_content, "ZANVIL_THEME_LIGHT", &sync.theme_light);
    }
    if !sync.theme_dark.is_empty() {
        config_content = config::set_value(&config_content, "ZANVIL_THEME_DARK", &sync.theme_dark);
    }
    config_content = config::set_value(
        &config_content,
        "ZANVIL_AUTO_UPDATE",
        &sync.auto_update.enabled.to_string(),
    );
    config_content = config::set_value(
        &config_content,
        "ZANVIL_UPDATE_FREQUENCY",
        &sync.auto_update.frequency.to_string(),
    );
    if !sync.auto_update.mode.is_empty() {
        // Les guillemets sont la convention du fichier pour cette cle, et le zsh les
        // ecrivait : sans eux, `ss` relirait une valeur nue la ou la config en attend
        // une citee.
        config_content = config::set_value(
            &config_content,
            "ZANVIL_UPDATE_MODE",
            &format!("\"{}\"", sync.auto_update.mode),
        );
    }

    if let Err(e) = config::write_config(&config_content) {
        eprintln!("{} {}", "✗".red(), e);
        return;
    }

    // Apply theme
    if !sync.theme.is_empty() {
        let _ = fs::write(config::zanvil_dir().join(".current_theme"), &sync.theme);
        println!("  {} Theme: {}", "✓".green(), sync.theme);
    }

    println!();
    println!("{} Config importee. Rechargez avec: {}", "✓".green(), "ss".bold());
}

fn diff(file: &str) {
    crate::cmd::print_header("Zanvil Sync Diff");
    crate::cmd::print_section("Source", file);
    println!();

    let content = match fs::read_to_string(file) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{} Impossible de lire {}: {}", "✗".red(), file, e);
            return;
        }
    };

    let sync: SyncConfig = match serde_json::from_str(&content) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("{} JSON invalide: {}", "✗".red(), e);
            return;
        }
    };

    let config_content = match config::read_config() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{} {}", "✗".red(), e);
            return;
        }
    };

    let local_modules = config::parse_modules(&config_content);
    let mut diffs = 0;

    println!(
        "  {:<28} {:<12} {:<12}",
        "Setting".bold(),
        "Local".bold(),
        "Import".bold()
    );
    println!("{}", "────────────────────────────────────────────────────".dimmed());

    for (name, remote_val) in &sync.modules {
        let local_val = local_modules
            .iter()
            .find(|m| m.name == *name)
            .map(|m| m.enabled);

        let local_str = local_val
            .map(|v| v.to_string())
            .unwrap_or_else(|| "(absent)".to_string());
        let remote_str = remote_val.to_string();

        if local_str != remote_str {
            println!(
                "  {:<28} {:<12} {}",
                format!("ZANVIL_MODULE_{}", name).yellow(),
                local_str,
                remote_str.cyan()
            );
            diffs += 1;
        } else {
            println!(
                "  {}",
                format!("  {:<28} {:<12} {}", format!("ZANVIL_MODULE_{}", name), local_str, remote_str).dimmed()
            );
        }
    }

    // Le theme etait absent de cette comparaison, donc le compte etait faux : deux
    // differences annoncees la ou il y en avait trois. Quelqu un qui lisait « 2 » et
    // importait decouvrait son prompt change a un reglage de plus que ce que la
    // commande lui avait montre.
    let local_theme = fs::read_to_string(config::zanvil_dir().join(".current_theme"))
        .map(|s| s.trim().to_string())
        .unwrap_or_default();
    let local_theme_str = if local_theme.is_empty() {
        "default".to_string()
    } else {
        local_theme
    };
    if local_theme_str != sync.theme {
        println!(
            "  {:<28} {:<12} {}",
            "theme".yellow(),
            local_theme_str,
            sync.theme.cyan()
        );
        diffs += 1;
    } else {
        println!(
            "  {}",
            format!("  {:<28} {:<12} {}", "theme", local_theme_str, sync.theme).dimmed()
        );
    }

    println!();
    if diffs > 0 {
        println!(
            "{} difference(s)  {}",
            diffs.to_string().yellow(),
            format!("(zanvil sync import {})", file).dimmed()
        );
    } else {
        println!("{} Configurations identiques", "✓".green());
    }
}

fn extract_value(content: &str, key: &str) -> String {
    content
        .lines()
        .find(|l| l.trim().starts_with(&format!("{}=", key)))
        .and_then(|l| l.split('=').nth(1))
        .map(|v| v.trim().trim_matches('"').to_string())
        .unwrap_or_default()
}
