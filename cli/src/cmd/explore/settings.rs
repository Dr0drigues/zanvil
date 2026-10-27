// Reglages de l'explorateur (projects.toml). Sans fichier : defauts vides.
use regex::Regex;
use serde::Deserialize;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

pub struct Rule {
    pub from: Regex,
    pub to: String,
}

pub struct Settings {
    pub gitlab_host: String,
    pub work_dir: PathBuf,
    pub clone_method: String, // "https" (defaut) | "ssh"
    pub ptf_root: Option<String>,
    pub app_segment: Option<String>,
    pub bus: BTreeMap<String, String>,
    pub config_var: Option<String>,
    pub config_path_pattern: Option<Regex>,
    pub config_rules: Vec<Rule>,
    pub test_rules: Vec<Rule>,
    pub common_configs: Vec<String>,
    pub app_var_keys: Vec<String>,
}

#[derive(Deserialize, Default)]
#[serde(default)]
struct RawRule {
    from: String,
    to: String,
}

#[derive(Deserialize, Default)]
#[serde(default)]
struct Raw {
    gitlab_host: String,
    work_dir: Option<PathBuf>,
    clone_method: String,
    ptf_root: Option<String>,
    app_segment: Option<String>,
    bus: BTreeMap<String, String>,
    config_var: Option<String>,
    config_path_pattern: Option<String>,
    config_rules: Vec<RawRule>,
    test_rules: Vec<RawRule>,
    common_configs: Vec<String>,
    app_var_keys: Vec<String>,
}

fn rules(raw: Vec<RawRule>) -> Vec<Rule> {
    raw.into_iter()
        .filter_map(|r| match Regex::new(&r.from) {
            Ok(from) => Some(Rule { from, to: r.to }),
            Err(e) => {
                eprintln!("zanvil explore: regle ignoree ({}) : {e}", r.from);
                None
            }
        })
        .collect()
}

impl Settings {
    fn from_raw(raw: Raw) -> Settings {
        let env = |k: &str| std::env::var(k).ok().filter(|v| !v.is_empty());
        let home = env("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/tmp"));
        Settings {
            gitlab_host: if raw.gitlab_host.is_empty() {
                env("GITLAB_BASE_DOMAIN").unwrap_or_default()
            } else {
                raw.gitlab_host
            },
            work_dir: match raw.work_dir {
                Some(w) if w == Path::new("~") => home.clone(),
                Some(w) => w.strip_prefix("~").map(|r| home.join(r)).unwrap_or(w),
                None => env("WORK_DIR").map(PathBuf::from).unwrap_or_else(|| home.join("work")),
            },
            clone_method: if raw.clone_method == "ssh" { "ssh".into() } else { "https".into() },
            ptf_root: raw.ptf_root,
            app_segment: raw.app_segment,
            bus: raw.bus,
            config_var: raw.config_var,
            config_path_pattern: raw.config_path_pattern.and_then(|p| match Regex::new(&p) {
                Ok(r) => Some(r),
                Err(e) => {
                    eprintln!("zanvil explore: config_path_pattern invalide : {e}");
                    None
                }
            }),
            config_rules: rules(raw.config_rules),
            test_rules: rules(raw.test_rules),
            common_configs: raw.common_configs,
            app_var_keys: raw.app_var_keys,
        }
    }

    pub fn load(path: &Path) -> Settings {
        let raw = match std::fs::read_to_string(path) {
            Err(_) => Raw::default(), // absent : cas normal
            Ok(s) => toml::from_str(&s).unwrap_or_else(|e| {
                eprintln!("zanvil explore: {} invalide : {e}", path.display());
                Raw::default()
            }),
        };
        Settings::from_raw(raw)
    }

    pub fn default_path() -> PathBuf {
        let base = std::env::var("XDG_CONFIG_HOME")
            .ok()
            .filter(|v| !v.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".into())).join(".config")
            });
        base.join("zanvil").join("projects.toml")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str, body: &str) -> PathBuf {
        let p = std::env::temp_dir().join(format!("zanvil-explore-{}-{name}.toml", std::process::id()));
        std::fs::write(&p, body).unwrap();
        p
    }

    #[test]
    fn fichier_absent() {
        let s = Settings::load(Path::new("/nonexistent/projects.toml"));
        assert!(s.bus.is_empty());
        assert!(s.config_rules.is_empty());
        assert_eq!(s.clone_method, "https");
    }

    #[test]
    fn exemple_generique() {
        let p = tmp("ok", r#"
ptf_root = "plat"
clone_method = "ssh"
[bus]
bu1 = "Unité 1"
[[config_rules]]
from = '^(.+)/components/(.+)$'
to = "$1/configurations/$2"
"#);
        let s = Settings::load(&p);
        assert_eq!(s.ptf_root.as_deref(), Some("plat"));
        assert_eq!(s.bus["bu1"], "Unité 1");
        assert_eq!(s.clone_method, "ssh");
        let r = &s.config_rules[0];
        assert_eq!(r.from.replace("a/components/b", r.to.as_str()), "a/configurations/b");
    }

    #[test]
    fn clone_method_inconnue_donne_https() {
        let p = tmp("cm", "clone_method = \"ftp\"\n");
        assert_eq!(Settings::load(&p).clone_method, "https");
    }

    #[test]
    fn work_dir_tilde_developpe() {
        let home = PathBuf::from(std::env::var("HOME").unwrap());
        assert_eq!(Settings::load(&tmp("t1", "work_dir = \"~/work\"\n")).work_dir, home.join("work"));
        assert_eq!(Settings::load(&tmp("t2", "work_dir = \"~\"\n")).work_dir, home);
        assert_eq!(Settings::load(&tmp("t3", "work_dir = \"/w/~x\"\n")).work_dir, PathBuf::from("/w/~x"));
        assert_eq!(Settings::load(&tmp("t4", "work_dir = \"~user/w\"\n")).work_dir, PathBuf::from("~user/w"));
    }

    #[test]
    fn toml_invalide() {
        let p = tmp("bad", "bus = [[[");
        let s = Settings::load(&p);
        assert!(s.bus.is_empty() && s.config_rules.is_empty());
    }
}
