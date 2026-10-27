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

pub fn refresh(s: &Settings) -> Result<Refreshed, String> {
    refresh_with(s, "glab")
}

/// Groupes d'application `<bu>/<app_segment>/<app>` ou l'on est au moins Maintainer sur un projet :
/// seuls ceux-la ont leurs variables lues (ailleurs l'API rend 403).
pub fn app_candidates(projects: &[IndexProject], s: &Settings) -> Vec<String> {
    let Some(seg) = s.app_segment.as_deref() else { return Vec::new() };
    let ptf = s.ptf_root.as_deref().map(|r| format!("{r}/"));
    let set: std::collections::BTreeSet<String> = projects
        .iter()
        .filter(|p| p.access >= 40 && !ptf.as_deref().is_some_and(|r| p.path.starts_with(r)))
        .filter_map(|p| {
            let parts: Vec<&str> = p.path.splitn(4, '/').collect();
            (parts.len() == 4 && parts[1] == seg && s.bus.contains_key(parts[0])).then(|| parts[..3].join("/"))
        })
        .collect();
    set.into_iter().collect()
}

#[derive(Debug)]
pub struct Refreshed {
    pub index: Index,
    /// groupes d'application dont les variables n'ont pas pu etre lues (403, erreur)
    pub refused: usize,
}

pub fn refresh_with(s: &Settings, glab: &str) -> Result<Refreshed, String> {
    let host = &s.gitlab_host;
    let list = |level: u8, simple: bool| {
        let extra = if simple { "&simple=true" } else { "" };
        glab_api(
            glab,
            host,
            &format!("projects?membership=true&min_access_level={level}&archived=false&per_page=100{extra}"),
            true,
        )
    };
    let mut projects: Vec<IndexProject> = list(30, false)?
        .iter()
        .filter_map(project_from_json)
        // la liste est filtree a Developer : c'est le plancher, meme quand `permissions` est null
        .map(|p| IndexProject { access: p.access.max(30), ..p })
        .collect();
    // un acces herite d'un partage de groupe laisse `permissions` a null : le filtre min_access_level, lui, en tient compte
    for level in [40u8, 50] {
        let paths: std::collections::HashSet<String> = list(level, true)?
            .iter()
            .filter_map(|v| v["path_with_namespace"].as_str().map(str::to_string))
            .collect();
        for p in projects.iter_mut().filter(|p| paths.contains(&p.path)) {
            p.access = p.access.max(level);
        }
    }

    let mut apps = Vec::new();
    let mut refused = 0;
    for group in app_candidates(&projects, s) {
        let ep = format!("groups/{}/variables?per_page=100", group.replace('/', "%2F"));
        // un groupe en echec n'arrete pas l'index
        match glab_api(glab, host, &ep, false) {
            Ok(vars) => apps.push(AppMeta { group, vars: keep_app_vars(&vars, &s.app_var_keys) }),
            Err(_) => refused += 1,
        }
    }
    Ok(Refreshed { index: Index { fetched_at: chrono::Utc::now().timestamp(), projects, apps }, refused })
}

/// Un index vide (jeton expire, mauvais hote) ne remplace jamais un cache.
pub fn save_refreshed(p: &Path, r: &Refreshed) -> Result<String, String> {
    if r.index.projects.is_empty() {
        return Err("aucun projet recu, cache conserve".into());
    }
    write_cache(p, &r.index).map_err(|e| e.to_string())?;
    Ok(format!(
        "{} projets, {} applications, {} groupes refusés",
        r.index.projects.len(),
        r.index.apps.len(),
        r.refused
    ))
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
    fn glab_absent() {
        let s = Settings::load(Path::new("/nonexistent/projects.toml"));
        let e = refresh_with(&s, "glab-inexistant-zanvil").unwrap_err();
        assert!(e.contains("glab"), "{e}");
    }

    fn settings(ptf: Option<&str>, seg: Option<&str>) -> Settings {
        let mut s = Settings::load(Path::new("/nonexistent/projects.toml"));
        s.ptf_root = ptf.map(Into::into);
        s.app_segment = seg.map(Into::into);
        s.bus.insert("bu1".into(), "Unite 1".into());
        s.bus.insert("plat".into(), "Plateforme".into());
        s.app_var_keys = vec!["APP_ID".into()];
        s
    }

    fn proj(path: &str, access: u8) -> IndexProject {
        IndexProject { access, path: path.into(), ..sample().projects[0].clone() }
    }

    #[test]
    fn candidats_applications() {
        let ps = vec![
            proj("bu1/apps/shop/api", 40),
            proj("bu1/apps/shop/components/front", 50), // imbrique : meme application
            proj("bu1/apps/cart/api", 30),              // Developer seulement
            proj("bu9/apps/x/api", 40),                 // hors BU
            proj("plat/apps/core/api", 40),             // sous la plateforme
            proj("bu1/libs/y/z", 40),                   // pas le segment d'application
            proj("bu1/apps/shop", 40),                  // le groupe lui-meme n'est pas un projet d'app
        ];
        assert_eq!(app_candidates(&ps, &settings(Some("plat"), Some("apps"))), vec!["bu1/apps/shop"]);
        // sans racine plateforme, plat est une BU comme une autre
        assert_eq!(
            app_candidates(&ps, &settings(None, Some("apps"))),
            vec!["bu1/apps/shop", "plat/apps/core"]
        );
        assert!(app_candidates(&ps, &settings(Some("plat"), None)).is_empty());
    }

    #[test]
    fn index_vide_ne_remplace_pas_le_cache() {
        let d = std::env::temp_dir().join(format!("zanvil-guard-{}", std::process::id()));
        let p = d.join("projects.json");
        write_cache(&p, &sample()).unwrap();
        let empty = Refreshed { index: Index { fetched_at: 9, projects: vec![], apps: vec![] }, refused: 0 };
        assert!(save_refreshed(&p, &empty).is_err());
        assert_eq!(load_cache(&p), Some(sample()));
        let ok = Refreshed { index: sample(), refused: 2 };
        assert_eq!(save_refreshed(&p, &ok).unwrap(), "1 projets, 1 applications, 2 groupes refusés");
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn rafraichissement_bout_en_bout() {
        use std::os::unix::fs::PermissionsExt;
        let d = std::env::temp_dir().join(format!("zanvil-fakeglab-{}", std::process::id()));
        std::fs::create_dir_all(&d).unwrap();
        let glab = d.join("glab");
        // pagination : deux tableaux concatenes ; acces herite (permissions null) pour shop/api et cart/api
        std::fs::write(&glab, r#"#!/bin/sh
case "$*" in
  *min_access_level=30*) printf '%s' '[{"path_with_namespace":"bu1/apps/shop/api","permissions":{"project_access":null,"group_access":null}},{"path_with_namespace":"bu1/apps/cart/api","permissions":{"project_access":null,"group_access":null}}][{"path_with_namespace":"bu1/apps/dev/api","permissions":{"project_access":{"access_level":30},"group_access":null}},{"path_with_namespace":"bu1/apps/own/api","permissions":{"project_access":{"access_level":50},"group_access":null}},{"path_with_namespace":"bu1/shared/lib","permissions":{"project_access":null,"group_access":null}}]' ;;
  *min_access_level=40*simple=true*) printf '%s' '[{"path_with_namespace":"bu1/apps/shop/api"}][{"path_with_namespace":"bu1/apps/cart/api"},{"path_with_namespace":"bu1/apps/own/api"}]' ;;
  *min_access_level=50*simple=true*) printf '%s' '[{"path_with_namespace":"bu1/apps/shop/api"}]' ;;
  *"groups/bu1%2Fapps%2Fshop/variables"*) printf '%s' '[{"key":"APP_ID","value":"A1"},{"key":"SECRET","value":"s"}]' ;;
  *"groups/bu1%2Fapps%2Fcart/variables"*) echo '403 Forbidden' >&2; exit 1 ;;
  *) echo "appel inattendu : $*" >&2; exit 1 ;;
esac
"#).unwrap();
        std::fs::set_permissions(&glab, std::fs::Permissions::from_mode(0o755)).unwrap();
        let s = settings(Some("plat"), Some("apps"));
        let r = refresh_with(&s, glab.to_str().unwrap()).unwrap();
        let _ = std::fs::remove_dir_all(&d);
        let access: Vec<(&str, u8)> = r.index.projects.iter().map(|p| (p.path.as_str(), p.access)).collect();
        assert_eq!(
            access,
            vec![
                ("bu1/apps/shop/api", 50),
                ("bu1/apps/cart/api", 40),
                ("bu1/apps/dev/api", 30),
                ("bu1/apps/own/api", 50), // plancher : permissions du projet
                ("bu1/shared/lib", 30),   // partage hors listes 40/50 : plancher Developer
            ]
        );
        // own : variables non decrites par le faux glab -> refus compte aussi
        assert_eq!(r.refused, 2);
        assert_eq!(r.index.apps.len(), 1);
        assert_eq!(r.index.apps[0].group, "bu1/apps/shop");
        assert_eq!(r.index.apps[0].vars.len(), 1);
        assert_eq!(r.index.apps[0].vars["APP_ID"], "A1");
    }
}
