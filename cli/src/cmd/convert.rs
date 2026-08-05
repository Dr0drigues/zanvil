//! Conversions de dates, appelées par les fonctions shell qui en avaient chacune leur copie.
//!
//! Cachée de l'aide : ce sont les primitives que le shell invoque, pas des commandes qu'on
//! tape. Les exposer donnerait à `zanvil --help` une entrée qui ne répond à aucune question
//! qu'un utilisateur se pose.
//!
//! **Pourquoi hors de `es`.** Ces conversions y ont vécu le temps du chantier 3, où seul le
//! module Elasticsearch les appelait. Le chantier 5 a trouvé le même calcul dans
//! `modules/gitlab/gitlab_logic.zsh` — l'expiration d'un jeton personnel, écrite deux fois
//! avec son propre embranchement GNU/BSD — et une primitive partagée par deux modules n'a
//! pas à porter le nom de l'un d'eux.
//!
//! Les fonctions de calcul restent dans `es.rs`, où `window` les utilise aussi.

use clap::Args;

#[derive(Args)]
pub struct ConvertArgs {
    /// Epoch seconds to render as ISO 8601 UTC
    #[arg(long, conflicts_with_all = ["from_iso", "from_paris"])]
    from_epoch: Option<i64>,
    /// ISO 8601 UTC timestamp, or a bare day, to read as epoch seconds
    #[arg(long, conflicts_with_all = ["from_epoch", "from_paris"])]
    from_iso: Option<String>,
    /// Europe/Paris local time to read as epoch seconds
    #[arg(long, conflicts_with_all = ["from_epoch", "from_iso"])]
    from_paris: Option<String>,
}

/// Une conversion par invocation, imprimée nue pour qu'un `$(…)` la capture.
///
/// Rend 1 sans rien écrire quand l'entrée est illisible : les fonctions shell appelantes
/// testent déjà la forme du résultat — `[[ "$epoch" == <-> ]]` en zsh, `[[ -n … ]]` en bash
/// — donc un message ici s'ajouterait à leur diagnostic au lieu de le remplacer.
pub fn run(args: ConvertArgs) -> i32 {
    if let Some(epoch) = args.from_epoch {
        println!("{}", super::es::epoch_to_iso(epoch));
        return 0;
    }
    if let Some(iso) = args.from_iso {
        return match super::es::iso_to_epoch(&iso) {
            Some(epoch) => {
                println!("{epoch}");
                0
            }
            None => 1,
        };
    }
    if let Some(local) = args.from_paris {
        return match super::es::paris_to_epoch(&local) {
            Some(epoch) => {
                println!("{epoch}");
                0
            }
            None => 1,
        };
    }
    eprintln!("rien a convertir: donnez --from-epoch, --from-iso ou --from-paris");
    1
}
