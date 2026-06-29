use clap::Subcommand;
use colored::Colorize;

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

fn list_modules() {
    let content = match config::read_config() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{}", e.red());
            return;
        }
    };

    let metas = config::scan_module_metas(&config::zanvil_dir());
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
            .strip_prefix("ZANVIL_MODULE_")
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
        let guard_var = format!("ZANVIL_MODULE_{}", m.name);
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
