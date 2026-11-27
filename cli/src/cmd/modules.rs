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
        // Valeur de config.zsh si la ligne existe, sinon la valeur par defaut du module : AI,
        // SECURITY, TOOLS ou PROJECT sont charges sans ligne, et s'affichaient « inactif ».
        let enabled = config_modules
            .iter()
            .find(|m| format!("ZANVIL_MODULE_{}", m.name) == guard_var)
            .map(|m| m.enabled)
            .unwrap_or(meta.default);
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

    // Module connu : declare par un .module.toml ou deja present dans config.zsh. Une cle
    // absente est ensuite ajoutee (set_value) : un module actif par defaut n'a pas de ligne.
    let key = format!("ZANVIL_MODULE_{}", upper);
    let known = config::scan_module_metas(&config::zanvil_dir())
        .iter()
        .any(|m| m.guard.as_deref() == Some(key.as_str()))
        || config::parse_modules(&content).iter().any(|m| m.name == upper);
    if !known {
        eprintln!("{}", format!("Module inconnu : {}", upper).red());
        std::process::exit(1);
    }
    let new_content = config::set_value(&content, &key, if enabled { "true" } else { "false" });

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
