mod cmd;
mod config;

use clap::{CommandFactory, Parser, Subcommand};
use clap_complete::{generate, Shell};
use cmd::theme::ThemeAction;
use cmd::modules::ModulesAction;
use cmd::sync::SyncAction;

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
    /// Benchmark shell startup time
    Bench {
        /// Number of runs
        #[arg(short, long, default_value = "5")]
        runs: u32,
    },
    /// Sync configuration between machines
    Sync {
        #[command(subcommand)]
        action: SyncAction,
    },
    /// Self-update zsh_env
    Update {
        /// Only check for updates, don't apply
        #[arg(long)]
        check: bool,
    },
    /// Scan for leaked secrets
    Secrets {
        /// Directory to scan
        #[arg(default_value = ".")]
        dir: String,
        /// Include glob patterns
        #[arg(long)]
        include: Vec<String>,
        /// Exclude glob patterns
        #[arg(long)]
        exclude: Vec<String>,
    },
    /// Interactive configuration TUI
    Config,
    /// Generate shell completions
    #[command(hide = true)]
    Completions,
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Theme { action } => cmd::theme::run(action),
        Commands::Doctor => cmd::doctor::run(),
        Commands::Audit => cmd::audit::run(),
        Commands::Context => cmd::context::run(),
        Commands::Modules { action } => cmd::modules::run(action),
        Commands::Bench { runs } => cmd::bench::run(runs),
        Commands::Update { check } => cmd::update::run(check),
        Commands::Config => cmd::tui_config::run(),
        Commands::Sync { action } => cmd::sync::run(action),
        Commands::Secrets { dir, include, exclude } => cmd::secrets::run(&dir, &include, &exclude),
        Commands::Completions => {
            generate(Shell::Zsh, &mut Cli::command(), "zsh-env-cli", &mut std::io::stdout());
        }
    }
}