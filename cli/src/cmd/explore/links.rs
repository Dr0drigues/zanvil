// Liens d'un repo : config, tests, template de CI, config commune (spec §6).
use super::settings::{Rule, Settings};
use super::tree::{Entry, Section};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum LinkKind {
    Config,
    Tests,
    Template,
    Common,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Link {
    pub kind: LinkKind,
    /// path_with_namespace de la cible (peut ne pas exister : l'UI le signale)
    pub target: String,
    /// deduit d'une regle plutot que lu dans la CI
    pub assumed: bool,
    pub git_ref: Option<String>,
}

fn link(kind: LinkKind, target: String, assumed: bool) -> Link {
    Link { kind, target, assumed, git_ref: None }
}

fn first_rule(rules: &[Rule], path: &str) -> Option<String> {
    rules.iter().find(|r| r.from.is_match(path)).map(|r| r.from.replace(path, r.to.as_str()).into_owned())
}

pub fn links_for(entry: &Entry, s: &Settings) -> Vec<Link> {
    let (configs, templates) = entry.local.as_deref().map_or_else(Default::default, |d| ci_references(d, s));
    let mut out: Vec<Link> = configs.into_iter().map(|c| link(LinkKind::Config, c, false)).collect();
    // les regles ne visent que des chemins GitLab, et un repo vide n'a pas de config attendue
    if entry.section == Section::Gitlab && !entry.empty {
        if out.is_empty() {
            out.extend(first_rule(&s.config_rules, &entry.path).map(|c| link(LinkKind::Config, c, true)));
        }
        out.extend(first_rule(&s.test_rules, &entry.path).map(|c| link(LinkKind::Tests, c, true)));
    }
    out.extend(templates.into_iter().map(|(p, r)| Link { git_ref: r, ..link(LinkKind::Template, p, false) }));
    out
}

pub fn common_for(app_group: &str, s: &Settings) -> Vec<Link> {
    s.common_configs.iter().map(|c| link(LinkKind::Common, format!("{app_group}/{c}"), true)).collect()
}

const CI_FILE: &str = ".gitlab-ci.yml";
const CI_DEPTH: usize = 3;

fn ci_files(dir: &Path, depth: usize, out: &mut Vec<PathBuf>) {
    let f = dir.join(CI_FILE);
    if f.is_file() {
        out.push(f);
    }
    if depth >= CI_DEPTH {
        return;
    }
    let Ok(rd) = std::fs::read_dir(dir) else { return };
    let mut dirs: Vec<PathBuf> = rd
        .flatten()
        .filter(|e| {
            let n = e.file_name();
            let n = n.to_string_lossy();
            !n.starts_with('.') && n != "node_modules" && e.file_type().is_ok_and(|t| t.is_dir())
        })
        .map(|e| e.path())
        .collect();
    dirs.sort();
    dirs.iter().for_each(|d| ci_files(d, depth + 1, out));
}

/// Valeur YAML scalaire : guillemets retires, commentaire de fin ignore.
fn scalar(v: &str) -> String {
    let v = v.trim();
    for q in ['"', '\''] {
        if let Some(rest) = v.strip_prefix(q) {
            return rest.split(q).next().unwrap_or("").to_string();
        }
    }
    v.split(" #").next().unwrap_or("").trim().to_string()
}

pub fn ci_references(repo_dir: &Path, s: &Settings) -> (Vec<String>, Vec<(String, Option<String>)>) {
    let mut files = Vec::new();
    ci_files(repo_dir, 0, &mut files);
    let mut configs: Vec<String> = Vec::new();
    let mut templates: Vec<(String, Option<String>)> = Vec::new();
    // shortcut: lecture ligne a ligne, ignore les include en ligne ({project: ...}) ; un parseur YAML si besoin
    for f in files {
        let Ok(txt) = std::fs::read_to_string(&f) else { continue };
        let mut include: Option<usize> = None; // indentation du bloc include: en cours
        let mut item_indent: Option<usize> = None; // indentation des elements de la liste include
        let mut tpl: Option<(String, Option<String>)> = None;
        for line in txt.lines() {
            let body = line.trim_start();
            if body.is_empty() || body.starts_with('#') {
                continue;
            }
            let indent = line.len() - body.len();
            if let Some(n) = include {
                // YAML accepte les elements de liste au meme niveau que la cle
                if indent > n || (indent == n && body.starts_with('-')) {
                    let item = body.strip_prefix('-').map(str::trim_start);
                    let kv = item.unwrap_or(body).split_once(':');
                    // seul un element de la liste include ouvre un nouveau template, pas ceux d'une liste file:
                    if item.is_some() && *item_indent.get_or_insert(indent) == indent {
                        templates.extend(tpl.take());
                    }
                    match kv {
                        Some(("project", v)) => tpl = Some((scalar(v), None)),
                        Some(("ref", v)) => {
                            if let Some(t) = tpl.as_mut() {
                                t.1 = Some(scalar(v));
                            }
                        }
                        _ => {}
                    }
                    continue;
                }
                templates.extend(tpl.take());
                include = None;
            }
            let Some((k, v)) = body.split_once(':') else { continue };
            if k == "include" && v.trim().is_empty() {
                include = Some(indent);
                item_indent = None;
                continue;
            }
            let v = scalar(v).replace("%2F", "/").replace("%2f", "/");
            if v.is_empty() || k.contains(' ') {
                continue;
            }
            let wanted = s.config_var.as_deref() == Some(k)
                || s.config_path_pattern.as_ref().is_some_and(|p| p.is_match(&v));
            if wanted && !configs.contains(&v) {
                configs.push(v);
            }
        }
        templates.extend(tpl.take());
    }
    // un meme template inclus par plusieurs fichiers n'apparait qu'une fois
    let mut seen = Vec::new();
    templates.retain(|t| !seen.contains(t) && { seen.push(t.clone()); true });
    (configs, templates)
}

#[cfg(test)]
mod tests {
    use super::*;
    use regex::Regex;
    use std::fs;

    fn settings() -> Settings {
        let mut s = Settings::load(Path::new("/nonexistent/projects.toml"));
        s.config_var = Some("CFG_VAR".into());
        s.config_path_pattern = Some(Regex::new("/configurations/").unwrap());
        s.config_rules = vec![
            Rule { from: Regex::new("^(.+)/libraries/.*$").unwrap(), to: "$1/configurations/assets".into() },
            Rule { from: Regex::new("^(.+)/components/(.+)$").unwrap(), to: "$1/configurations/$2".into() },
        ];
        s.test_rules = vec![Rule { from: Regex::new("^(plat/.+)/([^/]+)$").unwrap(), to: "$1/testing/$2".into() }];
        s.common_configs = vec!["configuration/shared".into()];
        s
    }

    fn entry(path: &str, local: Option<PathBuf>) -> Entry {
        Entry {
            path: path.into(),
            section: Section::Gitlab,
            local,
            misplaced: false,
            access: Some(30),
            empty: false,
            web_url: None,
            clone_url: None,
        }
    }

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("zanvil-links-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    fn write(root: &Path, rel: &str, body: &str) {
        let p = root.join(rel);
        fs::create_dir_all(p.parent().unwrap()).unwrap();
        fs::write(p, body).unwrap();
    }

    fn monorepo(name: &str) -> PathBuf {
        let d = tmp(name);
        write(&d, "front/.gitlab-ci.yml", "variables:\n  CFG_VAR: bu1/apps/shop/configurations/c-front\n");
        write(&d, "bff/.gitlab-ci.yml", "variables:\n  CFG_VAR: \"bu1/apps/shop/configurations/c-bff\" # bff\n");
        write(
            &d,
            ".gitlab-ci.yml",
            "include:\n  - project: shared/ci/base\n    ref: v2\n    file: /base.yml\n  - local: x.yml\n\
             variables:\n  OTHER_PROJECT: \"bu1%2Fapps%2Fshop%2Fconfigurations%2Fc-borne\"\n  IMAGE: node:20\n",
        );
        // ignores : node_modules et trop profond
        write(&d, "node_modules/p/.gitlab-ci.yml", "variables:\n  CFG_VAR: bu1/apps/shop/configurations/nm\n");
        write(&d, "a/b/c/d/.gitlab-ci.yml", "variables:\n  CFG_VAR: bu1/apps/shop/configurations/deep\n");
        d
    }

    #[test]
    fn references_monorepo() {
        let d = monorepo("mono");
        let (mut configs, templates) = ci_references(&d, &settings());
        configs.sort();
        assert_eq!(
            configs,
            [
                "bu1/apps/shop/configurations/c-bff",
                "bu1/apps/shop/configurations/c-borne",
                "bu1/apps/shop/configurations/c-front",
            ]
        );
        assert_eq!(templates, [("shared/ci/base".to_string(), Some("v2".to_string()))]);
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn include_sans_indentation_et_sans_ref() {
        let d = tmp("inc");
        write(&d, ".gitlab-ci.yml", "include:\n- project: 'shared/ci/base'\n  file: a.yml\nstages:\n  - build\n");
        let (configs, templates) = ci_references(&d, &settings());
        assert!(configs.is_empty());
        assert_eq!(templates, [("shared/ci/base".to_string(), None)]);
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn ref_apres_liste_file() {
        let d = tmp("filelist");
        write(&d, ".gitlab-ci.yml", "include:\n  - project: a/b\n    file:\n      - x.yml\n    ref: v1\n  - project: c/d\n");
        let (_, templates) = ci_references(&d, &settings());
        assert_eq!(templates, [("a/b".to_string(), Some("v1".to_string())), ("c/d".to_string(), None)]);
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn clone_avec_references_non_suppose() {
        let d = monorepo("cloned");
        let links = links_for(&entry("bu1/apps/shop/components/mono", Some(d.clone())), &settings());
        let configs: Vec<_> = links.iter().filter(|l| l.kind == LinkKind::Config).collect();
        assert_eq!(configs.len(), 3);
        assert!(configs.iter().all(|l| !l.assumed));
        let tpl = links.iter().find(|l| l.kind == LinkKind::Template).unwrap();
        assert_eq!((tpl.target.as_str(), tpl.git_ref.as_deref()), ("shared/ci/base", Some("v2")));
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn non_clone_regle_supposee() {
        let links = links_for(&entry("bu1/apps/shop/components/api", None), &settings());
        assert_eq!(
            links,
            [Link {
                kind: LinkKind::Config,
                target: "bu1/apps/shop/configurations/api".into(),
                assumed: true,
                git_ref: None
            }]
        );
    }

    #[test]
    fn premiere_regle_et_tests() {
        let links = links_for(&entry("plat/bu1/apps/shop/libraries/x", None), &settings());
        let kinds: Vec<_> = links.iter().map(|l| (l.kind, l.target.as_str())).collect();
        assert_eq!(
            kinds,
            [
                (LinkKind::Config, "plat/bu1/apps/shop/configurations/assets"),
                (LinkKind::Tests, "plat/bu1/apps/shop/libraries/testing/x"),
            ]
        );
    }

    #[test]
    fn sans_reglages_ni_vide_aucune_regle() {
        let bare = Settings::load(Path::new("/nonexistent/projects.toml"));
        assert!(links_for(&entry("bu1/apps/shop/components/api", None), &bare).is_empty());
        let mut e = entry("bu1/apps/shop/components/api", None);
        e.empty = true;
        assert!(links_for(&e, &settings()).is_empty());
        let mut e = entry("misc/components/x", None);
        e.section = Section::Outside;
        assert!(links_for(&e, &settings()).is_empty());
    }

    #[test]
    fn config_commune() {
        let l = common_for("plat/bu1/apps/shop", &settings());
        assert_eq!(l.len(), 1);
        assert_eq!((l[0].kind, l[0].target.as_str()), (LinkKind::Common, "plat/bu1/apps/shop/configuration/shared"));
    }
}
