//! Détection des déclarations en double dans les fichiers zsh du projet.
//!
//! Portage de `zanvil-doctor-conflicts` (chantier 4). C'est la seule fonction de
//! `core/commands/commands.zsh` que le critère du spec désigne : `zanvil-list` ne fait
//! qu'extraire des numéros de version de dix outils externes — de l'orchestration, que le
//! spec exclut explicitement — et les cinq appels de `zanvil-doctor` sont dans son repli,
//! puisqu'il délègue depuis sa première ligne.
//!
//! Ce que le shell faisait en quatre filtres chaînés par famille — `grep -r` pour
//! collecter, `sed` pour extraire le nom, `sort | uniq -d` pour ne garder que les
//! doublons, puis un second `grep -rl` pour retrouver les fichiers — tient ici en une
//! passe : on lit chaque fichier une fois et on accumule les noms par fichier.
//!
//! **Les trois périmètres sont différents, et c'est voulu.** Les alias et les fonctions
//! sont cherchés dans `core/` et `modules/`, les exports dans `modules/` seulement, et
//! les hooks `chpwd` dans tout le répertoire. Le zsh faisait déjà cette distinction ; la
//! reproduire à l'identique est ce qui permet aux cas de ne pas savoir qui répond.

use crate::config;
use colored::*;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

/// Un nom déclaré, et les fichiers qui le déclarent.
type Declarations = BTreeMap<String, Vec<String>>;

pub fn run() {
    crate::cmd::print_header("Conflicts");
    let root = config::zanvil_dir();
    let mut issues = 0u32;

    let core_and_modules = [root.join("core"), root.join("modules")];
    let modules_only = [root.join("modules")];

    issues += report(
        "Aliases",
        "alias",
        &collect(&core_and_modules, &root, alias_name),
    );
    println!();
    issues += report(
        "Fonctions",
        "fonction",
        &collect(&core_and_modules, &root, function_name),
    );
    println!();
    issues += report_hooks(&root);
    println!();
    issues += report(
        "Exports",
        "export",
        &collect(&modules_only, &root, export_name),
    );

    summary(issues);
}

/// Parcourt les répertoires donnés et accumule ce que `extract` reconnaît.
fn collect(dirs: &[PathBuf], root: &Path, extract: fn(&str) -> Option<String>) -> Declarations {
    let mut found: Declarations = BTreeMap::new();
    for dir in dirs {
        for file in zsh_files(dir) {
            let Ok(content) = fs::read_to_string(&file) else {
                continue;
            };
            let shown = relative(&file, root);
            for line in content.lines() {
                if let Some(name) = extract(line) {
                    let entry = found.entry(name).or_default();
                    // Un nom déclaré deux fois dans le même fichier ne nomme ce fichier
                    // qu'une fois : le conflit est entre déclarations, et la liste sert à
                    // savoir où aller regarder.
                    if !entry.contains(&shown) {
                        entry.push(shown.clone());
                    }
                }
            }
        }
    }
    found
}

/// `alias nom=…` en tête de ligne, nom en minuscules — le motif du zsh.
fn alias_name(line: &str) -> Option<String> {
    let rest = line.strip_prefix("alias ")?;
    let name = rest.split('=').next()?.trim();
    let first = name.chars().next()?;
    (first.is_ascii_lowercase() || first == '_').then(|| name.to_string())
}

/// `nom() {` en tête de ligne, nom en minuscules.
///
/// Le motif du zsh exige l'accolade ouvrante sur la même ligne, donc une fonction écrite
/// `nom()\n{` n'est pas vue — ici comme là-bas. Le projet n'en contient pas, et élargir
/// la détection ferait diverger les deux implémentations sur un cas que personne n'écrit.
fn function_name(line: &str) -> Option<String> {
    // `split_once` et non `strip_suffix` : le motif du zsh finit par `.*`, donc du code
    // sur la même ligne après l'accolade est accepté.
    let (name, _) = line.split_once("() {")?;
    let first = name.chars().next()?;
    (first.is_ascii_lowercase()
        && name
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-'))
    .then(|| name.to_string())
}

/// `export NOM=…` en tête de ligne, nom en majuscules.
fn export_name(line: &str) -> Option<String> {
    let rest = line.strip_prefix("export ")?;
    let (name, _) = rest.split_once('=')?;
    let first = name.chars().next()?;
    ((first.is_ascii_uppercase() || first == '_')
        && name
            .chars()
            .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_'))
    .then(|| name.to_string())
}

fn report(label: &str, kind: &str, found: &Declarations) -> u32 {
    crate::cmd::print_section(label, "");
    let dups: Vec<_> = found.iter().filter(|(_, files)| files.len() > 1).collect();
    if dups.is_empty() {
        let none = match kind {
            "alias" => "Aucun alias en double",
            "fonction" => "Aucune fonction en double",
            _ => "Aucun export en double",
        };
        println!("{} {}", "✓".green(), none);
        return 0;
    }
    for (name, files) in &dups {
        println!("{} '{}' → {}  ", "⚠".yellow(), name, files.join("  "));
    }
    dups.len() as u32
}

/// Les hooks `chpwd`, comptés et listés par le **même** critère.
///
/// Le zsh employait deux filtres divergents — `grep -cv "^#"` pour compter, qui n'écarte
/// que les lignes commençant par un dièse, et `grep -v "^.*#"` pour lister, qui écarte
/// toute ligne en contenant un. Il annonçait donc quatre hooks sur ce dépôt et n'en
/// affichait que deux : les deux de trop étaient ses propres lignes, celles qui cherchent
/// la chaîne, et elles n'apparaissaient pas parce qu'elles portent un dièse dans leur
/// motif. Le bon résultat sortait pour la mauvaise raison.
///
/// Exiger l'appel en tête de ligne écarte d'un coup les commentaires, les mentions dans
/// une chaîne, et le code qui cherche la chaîne sans rien enregistrer.
fn report_hooks(root: &Path) -> u32 {
    crate::cmd::print_section("Hooks", "");
    let mut hooks: Vec<(String, usize, String)> = Vec::new();
    for file in zsh_files(root) {
        let Ok(content) = fs::read_to_string(&file) else {
            continue;
        };
        let shown = relative(&file, root);
        for (index, line) in content.lines().enumerate() {
            if line.trim_start().starts_with("add-zsh-hook chpwd") {
                hooks.push((shown.clone(), index + 1, line.to_string()));
            }
        }
    }
    if hooks.len() > 1 {
        println!(
            "{} {} hooks chpwd enregistrés (attention aux interactions)",
            "⚠".yellow(),
            hooks.len()
        );
        for (file, line, text) in &hooks {
            println!("{file}:{line}:{text}");
        }
        1
    } else {
        println!("{} {} hook chpwd", "✓".green(), hooks.len());
        0
    }
}

fn summary(issues: u32) {
    println!("{}", "─".repeat(44).dimmed());
    if issues == 0 {
        println!("{}", "✓ Tout est OK".green());
    } else {
        println!(
            "{}, {}",
            format!("✗ {} erreur(s)", issues).red(),
            "0 avertissement(s)".yellow()
        );
    }
}

/// Tous les `*.zsh` sous `dir`, récursivement. Un répertoire illisible est ignoré, comme
/// `grep -r` le fait avec son `2>/dev/null`.
fn zsh_files(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let Ok(entries) = fs::read_dir(dir) else {
        return out;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            out.extend(zsh_files(&path));
        } else if path.extension().is_some_and(|ext| ext == "zsh") {
            out.push(path);
        }
    }
    out.sort();
    out
}

fn relative(file: &Path, root: &Path) -> String {
    file.strip_prefix(root)
        .unwrap_or(file)
        .display()
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_alias_declaration_is_recognised_by_its_name() {
        assert_eq!(alias_name("alias dupliq=\"echo x\""), Some("dupliq".into()));
        assert_eq!(alias_name("alias _prive='x'"), Some("_prive".into()));
        // Pas en tête de ligne, majuscule, ou sans nom : le zsh ne les voyait pas non plus.
        assert_eq!(alias_name("  alias indente=x"), None);
        assert_eq!(alias_name("alias MAJUSCULE=x"), None);
        assert_eq!(alias_name("# alias commente=x"), None);
    }

    #[test]
    fn a_function_declaration_is_recognised_by_its_name() {
        assert_eq!(function_name("fonction_x() {"), Some("fonction_x".into()));
        assert_eq!(function_name("kube-switch() {"), Some("kube-switch".into()));
        // Une fonction privée commence par un souligné, que le motif du zsh écarte.
        assert_eq!(function_name("_prive() {"), None);
        assert_eq!(function_name("  indentee() {"), None);
        assert_eq!(function_name("appel()"), None);
    }

    #[test]
    fn an_export_declaration_is_recognised_by_its_name() {
        assert_eq!(export_name("export MON_VAR=1"), Some("MON_VAR".into()));
        assert_eq!(export_name("export _INTERNE=x"), Some("_INTERNE".into()));
        assert_eq!(export_name("export minuscule=1"), None);
        assert_eq!(export_name("  export INDENTE=1"), None);
        // Sans affectation, ce n'est pas une déclaration.
        assert_eq!(export_name("export SANS_VALEUR"), None);
    }
}
