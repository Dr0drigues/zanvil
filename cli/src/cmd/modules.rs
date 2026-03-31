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

/// Returns a description for known modules.
fn module_description(name: &str) -> &'static str {
    match name {
        "GITLAB" => "Alias GitLab, clone groupes, statut PAT",
        "DOCKER" => "Utilitaires Docker (dex, dstop)",
        "MISE" => "Gestionnaire de versions (Node, Java...)",
        "NUSHELL" => "Integration Nushell (nush, nuc)",
        "KUBE" => "Gestion kubeconfig (kube_select, Azure/AWS/GCP)",
        _ => "",
    }
}

fn list_modules() {
    let content = match config::read_config() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{}", e.red());
            return;
        }
    };

    let modules = config::parse_modules(&content);

    if modules.is_empty() {
        println!("{}", "Aucun module trouve dans config.zsh".yellow());
        return;
    }

    println!(
        "  {:<12} {:<10} {}",
        "MODULE".bold(),
        "STATUT".bold(),
        "DESCRIPTION".bold()
    );
    println!("  {}", "-".repeat(60));

    for m in &modules {
        let status = if m.enabled {
            "actif".green().to_string()
        } else {
            "inactif".red().to_string()
        };
        let desc = module_description(&m.name);
        println!("  {:<12} {:<19} {}", m.name, status, desc);
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
