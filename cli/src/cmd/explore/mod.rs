// Explorateur de projets a deux volets. Les sous-modules arrivent par etapes.

pub mod app;
pub mod git;
pub mod index;
pub mod links;
pub mod local;
pub mod remote;
pub mod settings;
pub mod tree;
pub mod ui;

use clap::Args;
use std::path::PathBuf;
use std::sync::Arc;

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
    let settings = settings::Settings::load(&path);
    if args.refresh {
        match index::refresh(&settings).and_then(|r| index::save_refreshed(&index::cache_path(), &r)) {
            Ok(summary) => println!("{summary}"),
            Err(e) => {
                eprintln!("zanvil explore: {e}");
                std::process::exit(1);
            }
        }
        return;
    }
    // jamais de reseau ni de git a l'ouverture : cache + scan disque, le reste en arriere-plan
    let idx = index::load_cache(&index::cache_path());
    let locals = local::scan(&settings.work_dir, &settings.gitlab_host);
    let t = tree::build(idx.as_ref(), &locals, &settings);
    let app = app::App::new(t, Arc::new(settings), idx.map(|i| i.fetched_at));
    match ui::run(app) {
        Ok(Some(dir)) => {
            let res = match &args.out {
                Some(out) => std::fs::write(out, dir.to_string_lossy().as_bytes()),
                None => {
                    println!("{}", dir.display());
                    Ok(())
                }
            };
            if let Err(e) = res {
                eprintln!("zanvil explore: {e}");
                std::process::exit(1);
            }
        }
        Ok(None) => {}
        Err(e) => {
            eprintln!("zanvil explore: {e}");
            std::process::exit(1);
        }
    }
}
