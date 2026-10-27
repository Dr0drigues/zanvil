// Explorateur de projets a deux volets. Les sous-modules arrivent par etapes.
#![allow(dead_code)] // consomme par les taches suivantes

pub mod remote;
pub mod settings;

use clap::Args;
use std::path::PathBuf;

#[derive(Args)]
pub struct ExploreArgs {
    /// Fichier ou ecrire le chemin choisi
    #[arg(long)]
    pub out: Option<PathBuf>,
    /// Rafraichit l'index et sort
    #[arg(long)]
    pub refresh: bool,
    /// Fichier de reglages (defaut : $XDG_CONFIG_HOME/zanvil/projects.toml)
    #[arg(long)]
    pub settings: Option<PathBuf>,
}

pub fn run(args: ExploreArgs) {
    let path = args.settings.unwrap_or_else(settings::Settings::default_path);
    let _settings = settings::Settings::load(&path);
}
