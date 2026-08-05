use serde::Deserialize;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

/// Returns the path to the zanvil directory.
/// Uses $ZANVIL_DIR if set, otherwise falls back to ~/.zanvil.
pub fn zanvil_dir() -> PathBuf {
    if let Ok(dir) = env::var("ZANVIL_DIR") {
        PathBuf::from(dir)
    } else {
        let home = env::var("HOME").unwrap_or_else(|_| String::from("~"));
        PathBuf::from(home).join(".zanvil")
    }
}

/// Returns the path to config.zsh.
pub fn config_path() -> PathBuf {
    zanvil_dir().join("config.zsh")
}

/// Reads config.zsh and returns its content as a String.
/// Returns an error message if the file cannot be read.
pub fn read_config() -> Result<String, String> {
    let path = config_path();
    fs::read_to_string(&path).map_err(|e| format!("Impossible de lire {}: {}", path.display(), e))
}

/// Writes content back to config.zsh.
pub fn write_config(content: &str) -> Result<(), String> {
    let path = config_path();
    fs::write(&path, content).map_err(|e| format!("Impossible d'ecrire {}: {}", path.display(), e))
}

/// Represents a module entry parsed from config.zsh.
pub struct ModuleEntry {
    pub name: String,
    pub enabled: bool,
}

/// Module metadata parsed from a .module.toml file.
#[derive(Deserialize)]
pub struct ModuleMeta {
    pub guard: Option<String>,
    pub binary: Option<String>,
    pub install: Option<String>,
    pub description: Option<String>,
}

/// Scans modules/ at depth 2 and returns all .module.toml entries.
pub fn scan_module_metas(env_dir: &Path) -> Vec<ModuleMeta> {
    let modules_dir = env_dir.join("modules");
    let mut result = Vec::new();

    let Ok(top) = fs::read_dir(&modules_dir) else {
        return result;
    };
    for entry in top.flatten() {
        let path = entry.path();
        if path.is_dir() {
            // depth 1: modules/*/
            let meta_path = path.join(".module.toml");
            if meta_path.exists() {
                if let Ok(content) = fs::read_to_string(&meta_path) {
                    if let Ok(meta) = toml::from_str::<ModuleMeta>(&content) {
                        result.push(meta);
                    }
                }
            }
            // depth 2: modules/tools/*/
            if let Ok(sub) = fs::read_dir(&path) {
                for sub_entry in sub.flatten() {
                    let sub_path = sub_entry.path();
                    if sub_path.is_dir() {
                        let sub_meta = sub_path.join(".module.toml");
                        if sub_meta.exists() {
                            if let Ok(content) = fs::read_to_string(&sub_meta) {
                                if let Ok(meta) = toml::from_str::<ModuleMeta>(&content) {
                                    result.push(meta);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    result
}

/// Parses all ZANVIL_MODULE_*=true|false lines from config.zsh content.
pub fn parse_modules(content: &str) -> Vec<ModuleEntry> {
    let mut modules = Vec::new();
    for line in content.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("ZANVIL_MODULE_") {
            if let Some((name, value)) = rest.split_once('=') {
                let enabled = value.trim() == "true";
                modules.push(ModuleEntry {
                    name: name.to_string(),
                    enabled,
                });
            }
        }
    }
    modules
}

/// Sets a module to enabled or disabled in the config content.
/// Returns the updated content, or an error if the module was not found.
/// Pose `key=value` dans le contenu de config.zsh, en remplaçant la ligne si elle
/// existe et en l'ajoutant sinon.
///
/// Contrairement à `set_module`, ne rend jamais d'erreur : une clé absente est un cas
/// normal ici. Un poste qui n'a jamais réglé son auto-update n'a pas la ligne, et un
/// import doit pouvoir la créer — c'est ce que fait `_zanvil_sync_set_config` en zsh,
/// dont cette fonction reprend le contrat pour que la délégation ne change rien.
///
/// La valeur est écrite telle quelle : c'est à l'appelant de mettre les guillemets
/// quand la convention du fichier les demande, comme pour `ZANVIL_UPDATE_MODE="…"`.
pub fn set_value(content: &str, key: &str, value: &str) -> String {
    let target = format!("{}=", key);
    let replacement = format!("{}={}", key, value);

    let mut found = false;
    let mut lines: Vec<String> = content
        .lines()
        .map(|line| {
            if line.trim().starts_with(&target) {
                found = true;
                replacement.clone()
            } else {
                line.to_string()
            }
        })
        .collect();

    if !found {
        lines.push(replacement);
    }

    let mut result = lines.join("\n");
    if content.ends_with('\n') || !found {
        result.push('\n');
    }
    result
}

/// Lit un tableau zsh `NOM=(a b c)` déclaré sur une seule ligne.
///
/// Le format est celui que `install.sh` et les exemples écrivent, et le seul que
/// `plugins.zsh` sache relire. Un tableau étalé sur plusieurs lignes n'est pas géré —
/// le zsh ne le gérait pas non plus, et inventer ici une tolérance que le reste du
/// projet n'a pas ferait diverger l'export de ce que la config veut dire.
pub fn parse_array(content: &str, key: &str) -> Vec<String> {
    let target = format!("{}=(", key);
    content
        .lines()
        .map(str::trim)
        .find(|line| line.starts_with(&target))
        .and_then(|line| line.split_once('(').map(|(_, rest)| rest))
        .map(|rest| rest.trim_end_matches(')'))
        .map(|inner| {
            inner
                .split_whitespace()
                .map(|item| item.trim_matches(['"', '\'']).to_string())
                .filter(|item| !item.is_empty())
                .collect()
        })
        .unwrap_or_default()
}

pub fn set_module(content: &str, name: &str, enabled: bool) -> Result<String, String> {
    let key = format!("ZANVIL_MODULE_{}", name.to_uppercase());
    let target = format!("{}=", key);
    let replacement = format!("{}={}", key, if enabled { "true" } else { "false" });

    let mut found = false;
    let lines: Vec<String> = content
        .lines()
        .map(|line| {
            if line.trim().starts_with(&target) {
                found = true;
                replacement.clone()
            } else {
                line.to_string()
            }
        })
        .collect();

    if !found {
        return Err(format!("Module '{}' introuvable dans config.zsh", name.to_uppercase()));
    }

    // Preserve trailing newline if original had one
    let mut result = lines.join("\n");
    if content.ends_with('\n') {
        result.push('\n');
    }
    Ok(result)
}
