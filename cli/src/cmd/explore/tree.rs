// Arbre de gauche : union index GitLab + repos locaux, classes par plateforme.
use super::index::{AppMeta, Index};
use super::local::LocalRepo;
use super::remote::Remote;
use super::settings::Settings;
use std::collections::HashMap;
use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Section {
    Gitlab,
    Outside,
}

#[derive(Debug, Clone)]
pub struct Entry {
    /// path_with_namespace (GitLab) ou chemin relatif a work_dir (Outside)
    pub path: String,
    pub section: Section,
    pub local: Option<PathBuf>,
    pub misplaced: bool,
    pub access: Option<u8>,
    pub empty: bool,
    pub web_url: Option<String>,
    pub clone_url: Option<String>,
}

#[derive(Debug, Default)]
pub struct Node {
    pub label: String,
    /// prefixe de chemin du groupe ("" pour les racines et le noeud synthetique CaaS)
    pub key: String,
    pub children: Vec<Node>,
    /// indices dans Tree.entries
    pub entries: Vec<usize>,
}

#[derive(Debug)]
pub struct Tree {
    pub entries: Vec<Entry>,
    pub gitlab: Node,
    pub outside: Node,
}

pub fn build(idx: Option<&Index>, locals: &[LocalRepo], s: &Settings) -> Tree {
    let mut entries: Vec<Entry> = Vec::new();
    let mut by_path: HashMap<String, usize> = HashMap::new();
    if let Some(idx) = idx {
        for p in &idx.projects {
            let clone = if s.clone_method == "ssh" { &p.ssh_url } else { &p.http_url };
            by_path.insert(p.path.clone(), entries.len());
            entries.push(Entry {
                path: p.path.clone(),
                section: Section::Gitlab,
                local: None,
                misplaced: false,
                access: Some(p.access),
                empty: p.empty,
                web_url: Some(p.web_url.clone()),
                clone_url: Some(clone.clone()),
            });
        }
    }
    // scan n'a pas d'ordre stable : on trie pour un resultat deterministe
    let mut locals: Vec<&LocalRepo> = locals.iter().collect();
    locals.sort_by(|a, b| a.rel.cmp(&b.rel));
    for l in locals {
        let Remote::Gitlab(p) = &l.remote else {
            entries.push(Entry {
                path: l.rel.clone(),
                section: Section::Outside,
                local: Some(l.dir.clone()),
                misplaced: false,
                access: None,
                empty: false,
                web_url: None,
                clone_url: None,
            });
            continue;
        };
        let misplaced = l.rel != *p;
        match by_path.get(p) {
            // deux clones du meme projet : celui range a sa place l'emporte
            Some(&i) => {
                let e = &mut entries[i];
                if e.local.is_none() || (e.misplaced && !misplaced) {
                    e.local = Some(l.dir.clone());
                    e.misplaced = misplaced;
                }
            }
            // archive, role trop bas ou index absent : place deduite du chemin, sans role
            None => {
                by_path.insert(p.clone(), entries.len());
                entries.push(Entry {
                    path: p.clone(),
                    section: Section::Gitlab,
                    local: Some(l.dir.clone()),
                    misplaced,
                    access: None,
                    empty: false,
                    web_url: None,
                    clone_url: None,
                });
            }
        }
    }

    let apps = idx.map_or(&[][..], |i| &i.apps[..]);
    let mut gitlab = Node { label: "GitLab".into(), ..Node::default() };
    let mut outside = Node { label: "Hors GitLab".into(), ..Node::default() };
    for (i, e) in entries.iter().enumerate() {
        let group = e.path.rsplit_once('/').map_or("", |(g, _)| g);
        let (root, levels) = match e.section {
            Section::Gitlab => (&mut gitlab, levels(group, s, apps)),
            Section::Outside => (&mut outside, raw_levels(group, 0)),
        };
        let mut n = root;
        for (label, key) in levels {
            let pos = match n.children.iter().position(|c| c.key == key && c.label == label) {
                Some(pos) => pos,
                None => {
                    n.children.push(Node { label, key, ..Node::default() });
                    n.children.len() - 1
                }
            };
            n = &mut n.children[pos];
        }
        n.entries.push(i);
    }
    sort(&mut gitlab, &entries, true);
    sort(&mut outside, &entries, false);
    Tree { entries, gitlab, outside }
}

fn sort(n: &mut Node, entries: &[Entry], root: bool) {
    // a la racine GitLab, les plateformes passent avant les racines brutes
    let rank = |c: &Node| match (root, c.label.as_str()) {
        (true, PTF) => 0,
        (true, CAAS) => 1,
        _ => 2,
    };
    n.children.sort_by(|a, b| rank(a).cmp(&rank(b)).then_with(|| a.label.cmp(&b.label)));
    n.entries.sort_by(|&a, &b| entries[a].path.cmp(&entries[b].path));
    n.children.iter_mut().for_each(|c| sort(c, entries, false));
}

const PTF: &str = "PTF";
const CAAS: &str = "CaaS";

/// (libelle, cle) de chaque noeud entre la racine et le groupe, segments `from..` en chemin brut.
fn raw_levels(group: &str, from: usize) -> Vec<(String, String)> {
    let segs: Vec<&str> = group.split('/').filter(|x| !x.is_empty()).collect();
    (from..segs.len()).map(|i| (segs[i].to_string(), segs[..=i].join("/"))).collect()
}

/// plateforme > BU > application (segment app_segment masque) > chemin brut ; sinon chemin brut.
fn levels(group: &str, s: &Settings, apps: &[AppMeta]) -> Vec<(String, String)> {
    let segs: Vec<&str> = group.split('/').filter(|x| !x.is_empty()).collect();
    let ptf = s.ptf_root.as_deref().filter(|r| group == *r || group.starts_with(&format!("{r}/")));
    let (mut out, bu) = if let Some(r) = ptf {
        (vec![(PTF.to_string(), r.to_string())], r.split('/').count())
    } else if segs.first().is_some_and(|b| s.bus.contains_key(*b)) {
        (vec![(CAAS.to_string(), String::new())], 0)
    } else {
        return raw_levels(group, 0);
    };
    let Some(b) = segs.get(bu) else { return out };
    let label = s.bus.get(*b).filter(|l| !l.is_empty()).map_or(b.to_string(), |l| l.clone());
    out.push((label, segs[..=bu].join("/")));
    match s.app_segment.as_deref() {
        Some(a) if segs.get(bu + 1) == Some(&a) => {
            if let Some(app) = segs.get(bu + 2).map(|_| segs[..=bu + 2].join("/")) {
                out.push((node_label(&app, s, apps), app));
                out.extend(raw_levels(group, bu + 3));
            }
        }
        _ => out.extend(raw_levels(group, bu + 1)),
    }
    out
}

pub fn node_label(group_path: &str, _s: &Settings, apps: &[AppMeta]) -> String {
    let name = group_path.rsplit('/').next().unwrap_or(group_path).to_string();
    let Some(meta) = apps.iter().find(|a| a.group == group_path) else { return name };
    let parts: Vec<&str> = ["APP_NAME", "APP_ID", "PDT_NAME"]
        .iter()
        .filter_map(|k| meta.vars.get(*k).map(String::as_str).filter(|v| !v.is_empty()))
        .collect();
    if parts.is_empty() { name } else { parts.join(" · ") }
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::index::IndexProject;
    use std::collections::BTreeMap;
    use std::path::Path;

    fn bare() -> Settings {
        Settings::load(Path::new("/nonexistent/projects.toml"))
    }

    fn configured() -> Settings {
        let mut s = bare();
        s.ptf_root = Some("plat".into());
        s.app_segment = Some("apps".into());
        s.bus = BTreeMap::from([("bu1".to_string(), String::new())]);
        s
    }

    fn proj(path: &str) -> IndexProject {
        IndexProject {
            path: path.into(),
            ssh_url: format!("git@h.example:{path}.git"),
            http_url: format!("https://h.example/{path}.git"),
            web_url: format!("https://h.example/{path}"),
            access: 30,
            empty: false,
            default_branch: None,
        }
    }

    fn index() -> Index {
        Index {
            fetched_at: 0,
            projects: ["shared/lib/x", "plat/bu1/apps/shop/api", "bu1/apps/shop/components/front"]
                .iter()
                .map(|p| proj(p))
                .collect(),
            apps: vec![],
        }
    }

    fn local(rel: &str, remote: Remote) -> LocalRepo {
        LocalRepo { dir: PathBuf::from("/w").join(rel), rel: rel.into(), remote }
    }

    fn labels(n: &Node) -> Vec<&str> {
        n.children.iter().map(|c| c.label.as_str()).collect()
    }

    fn all_labels<'a>(n: &'a Node, out: &mut Vec<&'a str>) {
        out.push(&n.label);
        n.children.iter().for_each(|c| all_labels(c, out));
    }

    fn find<'a>(t: &'a Tree, path: &str) -> &'a Entry {
        t.entries.iter().find(|e| e.path == path).unwrap()
    }

    #[test]
    fn racines_par_plateforme() {
        let t = build(Some(&index()), &[], &configured());
        assert_eq!(labels(&t.gitlab), ["PTF", "CaaS", "shared"]);
        let mut all = vec![];
        all_labels(&t.gitlab, &mut all);
        assert!(!all.contains(&"apps"), "{all:?}");
        // PTF > bu1 > shop porte l'entree api
        let shop = &t.gitlab.children[0].children[0].children[0];
        assert_eq!((shop.label.as_str(), shop.key.as_str()), ("shop", "plat/bu1/apps/shop"));
        assert_eq!(t.entries[shop.entries[0]].path, "plat/bu1/apps/shop/api");
        // CaaS > bu1 > shop > components porte front
        let comp = &t.gitlab.children[1].children[0].children[0].children[0];
        assert_eq!((comp.label.as_str(), comp.key.as_str()), ("components", "bu1/apps/shop/components"));
        let e = find(&t, "bu1/apps/shop/components/front");
        assert_eq!(e.clone_url.as_deref(), Some("https://h.example/bu1/apps/shop/components/front.git"));
        assert_eq!(e.access, Some(30));
    }

    #[test]
    fn clone_ssh() {
        let mut s = configured();
        s.clone_method = "ssh".into();
        let t = build(Some(&index()), &[], &s);
        assert_eq!(find(&t, "shared/lib/x").clone_url.as_deref(), Some("git@h.example:shared/lib/x.git"));
    }

    #[test]
    fn clone_ailleurs() {
        let l = [local("misc/front", Remote::Gitlab("bu1/apps/shop/components/front".into()))];
        let t = build(Some(&index()), &l, &configured());
        let e = find(&t, "bu1/apps/shop/components/front");
        assert!(e.misplaced);
        assert_eq!(e.local.as_deref(), Some(Path::new("/w/misc/front")));
        assert_eq!(t.entries.len(), 3);
        assert!(t.outside.children.is_empty() && t.outside.entries.is_empty());
    }

    #[test]
    fn a_sa_place_non_misplaced() {
        let l = [local("shared/lib/x", Remote::Gitlab("shared/lib/x".into()))];
        let t = build(Some(&index()), &l, &configured());
        let e = find(&t, "shared/lib/x");
        assert!(!e.misplaced && e.local.is_some());
    }

    #[test]
    fn foreign_et_sans_remote_hors_gitlab() {
        let l = [
            local("misc/x", Remote::Foreign("https://github.com/o/x.git".into())),
            local("loose", Remote::None),
        ];
        let t = build(Some(&index()), &l, &configured());
        let e = find(&t, "misc/x");
        assert_eq!(e.section, Section::Outside);
        assert_eq!(labels(&t.outside), ["misc"]);
        assert_eq!(t.entries[t.outside.children[0].entries[0]].path, "misc/x");
        assert_eq!(t.entries[t.outside.entries[0]].path, "loose");
        assert_eq!(e.clone_url, None);
    }

    #[test]
    fn gitlab_absent_de_l_index() {
        let l = [local("old/repo", Remote::Gitlab("old/repo".into()))];
        let t = build(Some(&index()), &l, &configured());
        let e = find(&t, "old/repo");
        assert_eq!((e.section, e.access, e.misplaced), (Section::Gitlab, None, false));
        assert_eq!(labels(&t.gitlab), ["PTF", "CaaS", "old", "shared"]);
        // sans index du tout : toujours a sa place
        let t = build(None, &l, &bare());
        assert_eq!(labels(&t.gitlab), ["old"]);
    }

    #[test]
    fn sans_reglages_chemin_brut() {
        let t = build(Some(&index()), &[], &bare());
        assert_eq!(labels(&t.gitlab), ["bu1", "plat", "shared"]);
        assert_eq!(labels(&t.gitlab.children[1].children[0]), ["apps"]);
    }

    #[test]
    fn libelle_application() {
        let vars = BTreeMap::from([
            ("APP_NAME".to_string(), "Shop".to_string()),
            ("APP_ID".to_string(), "A1".to_string()),
            ("PDT_NAME".to_string(), "Pos".to_string()),
        ]);
        let apps = vec![AppMeta { group: "bu1/apps/shop".into(), vars }];
        let s = configured();
        assert_eq!(node_label("bu1/apps/shop", &s, &apps), "Shop · A1 · Pos");
        assert_eq!(node_label("bu1/apps/other", &s, &apps), "other");
        // le libelle sert bien dans l'arbre
        let mut idx = index();
        idx.apps = apps;
        let t = build(Some(&idx), &[], &s);
        assert_eq!(t.gitlab.children[1].children[0].children[0].label, "Shop · A1 · Pos");
    }
}
