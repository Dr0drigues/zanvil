use clap::Subcommand;

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

pub fn run(action: ModulesAction) {
    match action {
        ModulesAction::List => println!("modules list: not yet implemented"),
        ModulesAction::Enable { name } => println!("modules enable '{}': not yet implemented", name),
        ModulesAction::Disable { name } => println!("modules disable '{}': not yet implemented", name),
    }
}
