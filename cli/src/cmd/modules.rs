use clap::Subcommand;
use colored::Colorize;
use serde::Deserialize;
use std::fs;

use crate::config;

#[derive(Subcommand)]
pub enum ModulesAction {
    /// List available modules
    List,
    /// Enable a module
    Enable {
        /// Module name
        name: String,
    },
    /// Disable a module
    Disable {
        /// Module name
        name: String,
    },
}

#[derive(Deserialize)]
#[allow(dead_code)]
struct ModuleMeta {
    guard: Option<String>,
    binary: Option<String>,
    install: Option<String>,
    description: Option<String>,
}

/// Scans modules/ at depth 2 and returns all .module.toml entries.
fn scan_module_metas() -> Vec<ModuleMeta> {
    let env_dir = config::zsh_env_dir();
    let modules_dir = env_dir.join("modules");
    let mut result = Vec::new();

    let Ok(top) = fs::read_dir(&modules_dir) else { return result };
    for entry in top.flatten() {
        let path = entry.path();
        if path.is_dir() {
            // depth 1: modules/*/
            let meta_path = path.join(".module.toml");
            if meta_path.exists() {
                if let Ok(content) = fs::read_to_string(&meta_path) {
                    if let Ok(meta) = toml::from_str::<ModuleMeta>(&content) {
                        result.push(meta);
                    }
                }
            }
            // depth 2: modules/tools/*/
            if let Ok(sub) = fs::read_dir(&path) {
                for sub_entry in sub.flatten() {
                    let sub_path = sub_entry.path();
                    if sub_path.is_dir() {
                        let sub_meta = sub_path.join(".module.toml");
                        if sub_meta.exists() {
                            if let Ok(content) = fs::read_to_string(&sub_meta) {
                                if let Ok(meta) = toml::from_str::<ModuleMeta>(&content) {
                                    result.push(meta);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    result
}

fn list_modules() {
    let content = match config::read_config() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{}", e.red());
            return;
        }
    };

    let metas = scan_module_metas();
    let config_modules = config::parse_modules(&content);

    println!(
        "  {:<12} {:<10} {}",
        "MODULE".bold(),
        "STATUT".bold(),
        "DESCRIPTION".bold()
    );
    println!("  {}", "-".repeat(60));

    let mut shown_guards: std::collections::HashSet<String> = std::collections::HashSet::new();
    for meta in &metas {
        let guard_var = meta.guard.as_deref().unwrap_or("");
        let name = guard_var
            .strip_prefix("ZSH_ENV_MODULE_")
            .unwrap_or(guard_var);
        let enabled = content.lines().any(|line| {
            let t = line.trim();
            t == format!("{}=true", guard_var) || t == format!("{}=\"true\"", guard_var)
        });
        let status = if enabled {
            "actif".green().to_string()
        } else {
            "inactif".red().to_string()
        };
        let desc = meta.description.as_deref().unwrap_or("");
        println!("  {:<12} {:<19} {}", name, status, desc);
        shown_guards.insert(guard_var.to_string());
    }

    // Show remaining config.zsh guards without .module.toml
    for m in &config_modules {
        let guard_var = format!("ZSH_ENV_MODULE_{}", m.name);
        if shown_guards.contains(&guard_var) {
            continue;
        }
        let status = if m.enabled {
            "actif".green().to_string()
        } else {
            "inactif".red().to_string()
        };
        println!("  {:<12} {:<19}", m.name, status);
    }
}

fn toggle_module(name: &str, enabled: bool) {
    let upper = name.to_uppercase();
    let content = match config::read_config() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{}", e.red());
            return;
        }
    };

    let new_content = match config::set_module(&content, &upper, enabled) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{}", e.red());
            return;
        }
    };

    if let Err(e) = config::write_config(&new_content) {
        eprintln!("{}", e.red());
        return;
    }

    let action = if enabled { "active" } else { "desactive" };
    println!(
        "{} Module {} {}",
        "✓".green(),
        upper.bold(),
        action.green()
    );
    println!("  Rechargez avec: {}", "ss".cyan());
}

pub fn run(action: ModulesAction) {
    match action {
        ModulesAction::List => list_modules(),
        ModulesAction::Enable { name } => toggle_module(&name, true),
        ModulesAction::Disable { name } => toggle_module(&name, false),
    }
}
