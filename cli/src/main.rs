mod cmd;
mod config;

use clap::{Parser, Subcommand};
use cmd::theme::ThemeAction;
use cmd::modules::ModulesAction;

#[derive(Parser)]
#[command(name = "zsh-env", version, about = "CLI companion for zsh_env")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Manage Starship themes
    Theme {
        #[command(subcommand)]
        action: ThemeAction,
    },
    /// Check system health
    Doctor,
    /// Run security audit
    Audit,
    /// Show current context
    Context,
    /// Manage zsh_env modules
    Modules {
        #[command(subcommand)]
        action: ModulesAction,
    },
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Theme { action } => cmd::theme::run(action),
        Commands::Doctor => cmd::doctor::run(),
        Commands::Audit => cmd::audit::run(),
        Commands::Context => cmd::context::run(),
        Commands::Modules { action } => cmd::modules::run(action),
    }
}
