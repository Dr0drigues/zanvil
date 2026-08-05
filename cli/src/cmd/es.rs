//! Calcul de la fenêtre temporelle des requêtes Elasticsearch.
//!
//! Portage du lot A du chantier 3. Les six fonctions zsh remplacées portaient 14 des 38
//! dépendances fragiles du module, dont un détecteur de variante écrit à la main parce
//! que `date -d` et `date -j -f` ne coexistent pas :
//!
//! ```text
//! if date --version &>/dev/null; then _WORK_ES_DATE_FLAVOR=gnu; else …=bsd; fi
//! ```
//!
//! Ce que ce détecteur contournait disparaît ici : `chrono` et `chrono-tz` ne dépendent
//! d'aucun binaire externe, donc il n'y a plus deux chemins à maintenir ni de variante à
//! deviner.
//!
//! **La sortie est lue, pas évaluée.** Trois lignes `clé=valeur` sur la sortie standard,
//! que le zsh relit avec `read`. Un format évaluable — `_work_es_gte='…'` passé à `eval`,
//! comme le font `starship init` ou `mise activate` — serait plus court d'une ligne et
//! exécuterait ce que l'utilisateur a écrit dans `--from`, puisque le libellé le reprend
//! tel quel.

use chrono::{DateTime, NaiveDateTime, TimeZone, Utc};
use chrono_tz::Europe::Paris;
use clap::Subcommand;

#[derive(Subcommand)]
pub enum EsAction {
    /// Compute the time window of a query from --since, or --from/--to
    Window {
        /// Relative duration back from now: 30s, 5m, 2h, 3d
        #[arg(long)]
        since: Option<String>,
        /// Start of the window, in Europe/Paris local time: 2026-03-26T15:30:00
        #[arg(long)]
        from: Option<String>,
        /// End of the window, same format. Defaults to now.
        #[arg(long)]
        to: Option<String>,
    },
    /// Convert between the two timestamp shapes the module handles.
    ///
    /// Caché : ce sont les primitives que les fonctions zsh appellent, pas des commandes
    /// qu'on tape. Les exposer donnerait à l'aide de `zanvil es` trois entrées qui ne
    /// répondent à aucune question qu'un utilisateur se pose.
    #[command(hide = true)]
    Convert {
        /// Epoch seconds to render as ISO 8601 UTC
        #[arg(long, conflicts_with_all = ["from_iso", "from_paris"])]
        from_epoch: Option<i64>,
        /// ISO 8601 UTC timestamp to read as epoch seconds
        #[arg(long, conflicts_with_all = ["from_epoch", "from_paris"])]
        from_iso: Option<String>,
        /// Europe/Paris local time to read as epoch seconds
        #[arg(long, conflicts_with_all = ["from_epoch", "from_iso"])]
        from_paris: Option<String>,
    },
}

pub fn run(action: EsAction) -> i32 {
    match action {
        EsAction::Window { since, from, to } => window(since, from, to),
        EsAction::Convert {
            from_epoch,
            from_iso,
            from_paris,
        } => convert(from_epoch, from_iso, from_paris),
    }
}

/// Une conversion par invocation, imprimée nue pour qu'un `$(…)` la capture.
///
/// Rend 1 sans rien écrire quand l'entrée est illisible : les fonctions zsh appelantes
/// testaient déjà `[[ "$epoch" == <-> ]]`, donc un message ici s'ajouterait à leur
/// diagnostic au lieu de le remplacer.
fn convert(from_epoch: Option<i64>, from_iso: Option<String>, from_paris: Option<String>) -> i32 {
    if let Some(epoch) = from_epoch {
        println!("{}", epoch_to_iso(epoch));
        return 0;
    }
    if let Some(iso) = from_iso {
        return match iso_to_epoch(&iso) {
            Some(epoch) => {
                println!("{epoch}");
                0
            }
            None => 1,
        };
    }
    if let Some(local) = from_paris {
        return match paris_to_epoch(&local) {
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

/// ISO 8601 UTC en epoch, avec ou sans millisecondes.
///
/// Les deux formes arrivent réellement : les requêtes du module portent des `.000Z`, les
/// réponses d'Elasticsearch pas toujours. Les millisecondes sont lues puis jetées, comme
/// le zsh le faisait en coupant la chaîne — la précision du module est la seconde.
fn iso_to_epoch(ts: &str) -> Option<i64> {
    let trimmed = ts.trim_end_matches('Z');
    let without_fraction = trimmed.split_once('.').map_or(trimmed, |(head, _)| head);
    NaiveDateTime::parse_from_str(without_fraction, "%Y-%m-%dT%H:%M:%S")
        .ok()
        .map(|naive| Utc.from_utc_datetime(&naive).timestamp())
}

/// `Xs`/`Xm`/`Xh`/`Xd` en secondes.
///
/// Refuse tout le reste, y compris un nombre nu et `1w`. Une durée sans unité serait
/// interprétée au hasard, et accepter `1w` comme une seconde serait pire qu'un refus.
fn parse_duration(spec: &str) -> Option<i64> {
    let (digits, unit) = spec.split_at(spec.len().checked_sub(1)?);
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let n: i64 = digits.parse().ok()?;
    match unit {
        "s" => Some(n),
        "m" => Some(n * 60),
        "h" => Some(n * 3600),
        "d" => Some(n * 86_400),
        _ => None,
    }
}

/// Le format qu'Elasticsearch attend dans une requête de plage : ISO 8601 UTC, avec des
/// millisecondes toujours à zéro.
fn epoch_to_iso(epoch: i64) -> String {
    DateTime::<Utc>::from_timestamp(epoch, 0)
        .unwrap_or_else(|| DateTime::<Utc>::from_timestamp(0, 0).expect("epoch zero is valid"))
        .format("%Y-%m-%dT%H:%M:%S.000Z")
        .to_string()
}

/// Une heure locale d'Europe/Paris en epoch UTC, heure d'été comprise.
///
/// C'est ce que le zsh obtenait de `TZ=Europe/Paris date`, et le seul endroit du lot où
/// une erreur ne se verrait pas : à heure locale égale, le 28 et le 30 mars 2026 sont à
/// une heure d'écart, parce que le basculement tombe entre les deux.
///
/// Une heure qui n'existe pas — 02:30 la nuit où l'on avance les pendules — est refusée
/// plutôt que décalée en silence. Une heure qui existe deux fois prend la première, celle
/// d'avant le recul.
fn paris_to_epoch(local: &str) -> Option<i64> {
    let naive = NaiveDateTime::parse_from_str(local, "%Y-%m-%dT%H:%M:%S").ok()?;
    Paris
        .from_local_datetime(&naive)
        .earliest()
        .map(|dt| dt.timestamp())
}

fn window(since: Option<String>, from: Option<String>, to: Option<String>) -> i32 {
    let now = Utc::now().timestamp();

    let (gte, lte, display) = match since.as_deref().filter(|s| !s.is_empty()) {
        Some(spec) => match parse_duration(spec) {
            Some(seconds) => (
                epoch_to_iso(now - seconds),
                epoch_to_iso(now),
                format!("depuis {spec} (-> now)"),
            ),
            None => {
                eprintln!("--since invalide: {spec} (attendu: Xs/Xm/Xh/Xd)");
                return 1;
            }
        },
        None => {
            let from = from.unwrap_or_default();
            let Some(from_epoch) = paris_to_epoch(&from) else {
                eprintln!("--from invalide: {from} (attendu: 2026-03-26T15:30:00)");
                return 1;
            };
            match to.as_deref().filter(|s| !s.is_empty()) {
                Some(to_str) => {
                    let Some(to_epoch) = paris_to_epoch(to_str) else {
                        eprintln!("--to invalide: {to_str} (attendu: 2026-03-26T15:30:00)");
                        return 1;
                    };
                    (
                        epoch_to_iso(from_epoch),
                        epoch_to_iso(to_epoch),
                        format!("{from} -> {to_str} (Europe/Paris)"),
                    )
                }
                None => (
                    epoch_to_iso(from_epoch),
                    epoch_to_iso(now),
                    format!("{from} -> now (Europe/Paris)"),
                ),
            }
        }
    };

    println!("gte={gte}");
    println!("lte={lte}");
    println!("display={display}");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn duration_units_are_the_four_the_module_documents() {
        assert_eq!(parse_duration("30s"), Some(30));
        assert_eq!(parse_duration("5m"), Some(300));
        assert_eq!(parse_duration("2h"), Some(7200));
        assert_eq!(parse_duration("3d"), Some(259_200));
    }

    #[test]
    fn anything_else_is_refused_rather_than_guessed() {
        for spec in ["30x", "abc", "30", "1w", "2H", "", "s", "-1s", "1.5h"] {
            assert_eq!(parse_duration(spec), None, "{spec} should be refused");
        }
    }

    /// Les quatre valeurs viennent de `zoneinfo` en Python, pas de ce code : le cas
    /// gaveldrop et ce test partagent la même source indépendante.
    #[test]
    fn paris_time_crosses_the_dst_boundary() {
        assert_eq!(paris_to_epoch("2026-01-15T12:00:00"), Some(1_768_474_800));
        assert_eq!(paris_to_epoch("2026-07-15T12:00:00"), Some(1_784_109_600));
        // Le basculement 2026 tombe le 29 mars : la veille et le lendemain sont à une
        // heure d'écart pour la même heure locale.
        assert_eq!(paris_to_epoch("2026-03-28T12:00:00"), Some(1_774_695_600));
        assert_eq!(paris_to_epoch("2026-03-30T12:00:00"), Some(1_774_864_800));
        assert_eq!(
            paris_to_epoch("2026-03-30T12:00:00").unwrap() - paris_to_epoch("2026-03-28T12:00:00").unwrap(),
            2 * 86_400 - 3600,
            "deux jours moins l heure perdue au basculement"
        );
    }

    #[test]
    fn an_hour_that_does_not_exist_is_refused() {
        // 02:30 le 29 mars 2026 : les pendules passent de 02:00 à 03:00.
        assert_eq!(paris_to_epoch("2026-03-29T02:30:00"), None);
    }

    #[test]
    fn iso_carries_milliseconds_at_zero() {
        assert_eq!(epoch_to_iso(0), "1970-01-01T00:00:00.000Z");
        assert_eq!(epoch_to_iso(1_780_000_000), "2026-05-28T20:26:40.000Z");
    }

    #[test]
    fn iso_is_read_with_or_without_milliseconds() {
        assert_eq!(iso_to_epoch("2026-05-28T20:26:40.000Z"), Some(1_780_000_000));
        assert_eq!(iso_to_epoch("2026-05-28T20:26:40Z"), Some(1_780_000_000));
        // Sans le Z non plus : une réponse Elasticsearch peut l'omettre.
        assert_eq!(iso_to_epoch("2026-05-28T20:26:40"), Some(1_780_000_000));
        // Les millisecondes sont jetées, pas arrondies : la précision du module est la
        // seconde, et le zsh coupait la chaîne au point.
        assert_eq!(iso_to_epoch("2026-05-28T20:26:40.999Z"), Some(1_780_000_000));
    }

    #[test]
    fn a_malformed_iso_is_refused() {
        for ts in ["pas-une-date", "2026-05-28", "", "20:26:40"] {
            assert_eq!(iso_to_epoch(ts), None, "{ts} should be refused");
        }
    }

    #[test]
    fn iso_round_trips_through_epoch() {
        let start = "2026-05-28T20:26:40.000Z";
        assert_eq!(epoch_to_iso(iso_to_epoch(start).unwrap()), start);
    }

    #[test]
    fn a_malformed_local_time_is_refused() {
        for spec in ["pas-une-date", "2026-03-26", "2026-03-26T15:30", ""] {
            assert_eq!(paris_to_epoch(spec), None, "{spec} should be refused");
        }
    }
}
