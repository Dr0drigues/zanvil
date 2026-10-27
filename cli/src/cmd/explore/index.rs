// Index des projets GitLab (via glab) et cache disque atomique.
use super::settings::Settings;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Serialize, Deserialize, Debug, PartialEq, Clone)]
pub struct IndexProject {
    pub path: String,
    pub ssh_url: String,
    pub http_url: String,
    pub web_url: String,
    pub access: u8,
    pub empty: bool,
    pub default_branch: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, PartialEq, Clone)]
pub struct AppMeta {
    pub group: String,
    pub vars: BTreeMap<String, String>,
}

#[derive(Serialize, Deserialize, Debug, PartialEq, Clone)]
pub struct Index {
    pub fetched_at: i64,
    pub projects: Vec<IndexProject>,
    pub apps: Vec<AppMeta>,
}

/// `glab api --paginate` concatene un tableau JSON par page, sans separateur.
pub fn parse_paginated(raw: &str) -> Result<Vec<Value>, String> {
    let mut out = Vec::new();
    for page in serde_json::Deserializer::from_str(raw).into_iter::<Vec<Value>>() {
        out.extend(page.map_err(|e| format!("JSON invalide : {e}"))?);
    }
    Ok(out)
}

pub fn project_from_json(v: &Value) -> Option<IndexProject> {
    let s = |k: &str| v.get(k).and_then(Value::as_str).map(str::to_string);
    let level = |k: &str| v["permissions"][k]["access_level"].as_u64().unwrap_or(0);
    Some(IndexProject {
        path: s("path_with_namespace")?,
        ssh_url: s("ssh_url_to_repo").unwrap_or_default(),
        http_url: s("http_url_to_repo").unwrap_or_default(),
        web_url: s("web_url").unwrap_or_default(),
        access: level("project_access").max(level("group_access")).min(255) as u8,
        empty: v.get("empty_repo").and_then(Value::as_bool).unwrap_or(false),
        default_branch: s("default_branch"),
    })
}

/// Seules les cles listees sont gardees : rien d'autre ne touche le disque.
pub fn keep_app_vars(vars: &[Value], keys: &[String]) -> BTreeMap<String, String> {
    vars.iter()
        .filter_map(|v| Some((v.get("key")?.as_str()?, v.get("value")?.as_str()?)))
        .filter(|(k, _)| keys.iter().any(|w| w == k))
        .map(|(k, val)| (k.to_string(), val.to_string()))
        .collect()
}

pub fn cache_path() -> PathBuf {
    let base = std::env::var("XDG_CACHE_HOME")
        .ok()
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".into())).join(".cache"));
    base.join("zanvil").join("projects.json")
}

pub fn load_cache(p: &Path) -> Option<Index> {
    serde_json::from_str(&std::fs::read_to_string(p).ok()?).ok()
}

pub fn write_cache(p: &Path, idx: &Index) -> io::Result<()> {
    if let Some(d) = p.parent() {
        std::fs::create_dir_all(d)?;
    }
    let tmp = p.with_extension(format!("json.tmp{}", std::process::id()));
    std::fs::write(&tmp, serde_json::to_vec(idx).map_err(io::Error::other)?)?;
    std::fs::rename(&tmp, p).inspect_err(|_| {
        let _ = std::fs::remove_file(&tmp);
    })
}

pub fn is_stale(idx: &Index, now: i64) -> bool {
    now - idx.fetched_at > 86_400
}

fn glab_api(glab: &str, host: &str, endpoint: &str, paginate: bool) -> Result<Vec<Value>, String> {
    let mut cmd = Command::new(glab);
    cmd.arg("api");
    if paginate {
        cmd.arg("--paginate");
    }
    cmd.arg(endpoint);
    if !host.is_empty() {
        cmd.env("GITLAB_HOST", host);
    }
    let out = cmd.output().map_err(|e| format!("{glab} introuvable ou inutilisable : {e}"))?;
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        return Err(format!("{glab} api {endpoint} a echoue : {}", err.trim()));
    }
    parse_paginated(&String::from_utf8_lossy(&out.stdout))
}

pub fn refresh(s: &Settings) -> Result<Index, String> {
    refresh_with(s, "glab")
}

pub fn refresh_with(s: &Settings, glab: &str) -> Result<Index, String> {
    let host = &s.gitlab_host;
    let projects = glab_api(
        glab,
        host,
        "projects?membership=true&min_access_level=30&archived=false&per_page=100",
        true,
    )?
    .iter()
    .filter_map(project_from_json)
    .collect();

    let mut apps = Vec::new();
    if let (Some(ptf), Some(seg)) = (&s.ptf_root, &s.app_segment) {
        let groups = glab_api(glab, host, "groups?min_access_level=40&per_page=100", true)?;
        for g in &groups {
            let (Some(path), Some(id)) = (g["full_path"].as_str(), g["id"].as_u64()) else { continue };
            let parts: Vec<&str> = path.split('/').collect();
            let is_app = parts.len() == 3
                && parts[1] == seg
                && parts[0] != ptf
                && s.bus.contains_key(parts[0]);
            if !is_app {
                continue;
            }
            // un groupe en echec n'arrete pas l'index
            if let Ok(vars) = glab_api(glab, host, &format!("groups/{id}/variables?per_page=100"), false) {
                apps.push(AppMeta { group: path.to_string(), vars: keep_app_vars(&vars, &s.app_var_keys) });
            }
        }
    }
    Ok(Index { fetched_at: chrono::Utc::now().timestamp(), projects, apps })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn pagination() {
        assert_eq!(parse_paginated("[{\"a\":1}][{\"a\":2},{\"a\":3}]").unwrap().len(), 3);
        assert_eq!(parse_paginated("[]").unwrap().len(), 0);
        assert!(parse_paginated("[{").is_err());
    }

    #[test]
    fn acces_et_vide() {
        let p = |pa: Value, ga: Value, empty: bool| {
            project_from_json(&json!({"path_with_namespace":"a/b","empty_repo":empty,
                "permissions":{"project_access":pa,"group_access":ga}})).unwrap()
        };
        assert_eq!(p(Value::Null, json!({"access_level":30}), false).access, 30);
        assert_eq!(p(json!({"access_level":40}), json!({"access_level":30}), false).access, 40);
        assert!(p(Value::Null, Value::Null, true).empty);
    }

    #[test]
    fn variables_filtrees() {
        let vars = vec![
            json!({"key":"APP_ID","value":"A1"}),
            json!({"key":"SUBSCRIPTION_ID","value":"x"}),
            json!({"key":"APP_NAME","value":"N"}),
        ];
        let keys = vec!["APP_ID".to_string(), "APP_NAME".to_string()];
        let got = keep_app_vars(&vars, &keys);
        assert_eq!(got.len(), 2);
        assert_eq!(got["APP_ID"], "A1");
        assert_eq!(got["APP_NAME"], "N");
    }

    fn sample() -> Index {
        Index {
            fetched_at: 5,
            projects: vec![IndexProject {
                path: "a/b".into(), ssh_url: "s".into(), http_url: "h".into(), web_url: "w".into(),
                access: 40, empty: false, default_branch: Some("main".into()),
            }],
            apps: vec![AppMeta { group: "bu1/apps/shop".into(), vars: BTreeMap::new() }],
        }
    }

    #[test]
    fn cache_aller_retour() {
        let d = std::env::temp_dir().join(format!("zanvil-idx-{}", std::process::id()));
        let p = d.join("sub").join("projects.json");
        write_cache(&p, &sample()).unwrap();
        assert_eq!(load_cache(&p), Some(sample()));
        std::fs::write(&p, "{\"fetched_at\":1,\"proj").unwrap();
        assert_eq!(load_cache(&p), None);
        assert_eq!(load_cache(&d.join("absent.json")), None);
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn peremption() {
        let i = sample();
        assert!(!is_stale(&i, 5 + 86_400));
        assert!(is_stale(&i, 5 + 86_401));
    }

    #[test]
    fn glab_absent() {
        let s = Settings::load(Path::new("/nonexistent/projects.toml"));
        let e = refresh_with(&s, "glab-inexistant-zanvil").unwrap_err();
        assert!(e.contains("glab"), "{e}");
    }
}
