// Etat et touches de l'explorateur, sans terminal : ui.rs dessine et execute les Action.
use super::git::GitState;
use super::links::{self, LinkKind};
use super::settings::Settings;
use super::tree::{Node, Tree};
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::Arc;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Pane {
    Groups,
    Repos,
}

#[derive(Debug, PartialEq)]
pub enum Action {
    None,
    Quit,
    GoTo(PathBuf),
    Clone(Vec<usize>),
    PickMissing,
    OpenWeb(String),
    Refresh,
}

pub struct LinkRow {
    pub text: String,
    pub target: Option<usize>,
}

pub struct App {
    pub tree: Tree,
    pub settings: Arc<Settings>,
    pub focus: Pane,
    /// chemin dans l'arbre : [0 GitLab | 1 Hors GitLab, enfant, enfant...]
    pub selected_node: Vec<usize>,
    pub expanded: HashSet<Vec<usize>>,
    pub selected_entry: usize,
    pub filter: String,
    pub editing: bool,
    pub status: String,
    pub states: HashMap<usize, GitState>,
    /// etats deja demandes (pour ne pas relancer git a chaque image)
    pub asked: HashSet<usize>,
    pub cloning: HashMap<usize, String>,
    pub links: Option<Vec<LinkRow>>,
    pub link_sel: usize,
    pub fetched_at: Option<i64>,
    pub refreshing: bool,
    /// change a chaque nouvel arbre : les etats git d'avant sont ignores
    pub generation: u64,
}

const CLONING: &str = "clonage…";
const NOT_CLONED: &str = "non cloné — c pour cloner";

pub fn role(access: Option<u8>) -> &'static str {
    match access {
        Some(50) => "O",
        Some(40) => "M",
        Some(30) => "D",
        _ => " ",
    }
}

fn kind_label(k: LinkKind) -> &'static str {
    match k {
        LinkKind::Config => "config",
        LinkKind::Tests => "tests",
        LinkKind::Template => "template",
        LinkKind::Common => "commune",
    }
}

impl App {
    pub fn new(tree: Tree, settings: Arc<Settings>, fetched_at: Option<i64>) -> App {
        App {
            tree,
            settings,
            focus: Pane::Groups,
            selected_node: vec![0],
            expanded: HashSet::from([vec![0], vec![1]]),
            selected_entry: 0,
            filter: String::new(),
            editing: false,
            status: String::new(),
            states: HashMap::new(),
            asked: HashSet::new(),
            cloning: HashMap::new(),
            links: None,
            link_sel: 0,
            fetched_at,
            refreshing: false,
            generation: 0,
        }
    }

    pub fn node(&self, path: &[usize]) -> Option<&Node> {
        let (first, rest) = path.split_first()?;
        let mut n = match first {
            0 => &self.tree.gitlab,
            1 => &self.tree.outside,
            _ => return None,
        };
        for &i in rest {
            n = n.children.get(i)?;
        }
        Some(n)
    }

    fn needle(&self) -> String {
        self.filter.to_lowercase()
    }

    /// Entrees du sous-arbre qui passent le filtre (chemin, ou libelle d'un noeud au-dessus).
    fn collect(n: &Node, depth: usize, hit: bool, needle: &str, entries: &[super::tree::Entry], out: &mut Vec<usize>) {
        // les racines (GitLab, Hors GitLab) ne comptent pas comme libelle
        let hit = hit || needle.is_empty() || (depth > 0 && n.label.to_lowercase().contains(needle));
        out.extend(n.entries.iter().filter(|&&i| hit || entries[i].path.to_lowercase().contains(needle)));
        n.children.iter().for_each(|c| Self::collect(c, depth + 1, hit, needle, entries, out));
    }

    fn entries_under(&self, path: &[usize]) -> Vec<usize> {
        let needle = self.needle();
        let above = (2..path.len()).any(|k| self.node(&path[..k]).is_some_and(|n| n.label.to_lowercase().contains(&needle)));
        let mut out = Vec::new();
        if let Some(n) = self.node(path) {
            Self::collect(n, path.len() - 1, above, &needle, &self.tree.entries, &mut out);
        }
        out
    }

    pub fn visible_entries(&self) -> Vec<usize> {
        self.entries_under(&self.selected_node)
    }

    /// Lignes du panneau gauche : (chemin du noeud, profondeur), selon depliage et filtre.
    pub fn rows(&self) -> Vec<(Vec<usize>, usize)> {
        let mut out = Vec::new();
        for root in [0, 1] {
            self.rows_from(vec![root], &mut out);
        }
        out
    }

    fn rows_from(&self, path: Vec<usize>, out: &mut Vec<(Vec<usize>, usize)>) {
        let Some(n) = self.node(&path) else { return };
        if self.entries_under(&path).is_empty() {
            return;
        }
        let open = self.is_open(&path);
        out.push((path.clone(), path.len() - 1));
        if open {
            for i in 0..n.children.len() {
                let mut p = path.clone();
                p.push(i);
                self.rows_from(p, out);
            }
        }
    }

    pub fn is_open(&self, path: &[usize]) -> bool {
        // filtre actif : tout est deplie pour montrer les resultats
        !self.filter.is_empty() || self.expanded.contains(path)
    }

    pub fn missing_under_selected(&self) -> Vec<usize> {
        let e = &self.tree.entries;
        self.visible_entries().into_iter().filter(|&i| e[i].local.is_none() && e[i].clone_url.is_some()).collect()
    }

    pub fn current(&self) -> Option<usize> {
        self.visible_entries().get(self.selected_entry).copied()
    }

    pub fn handle_key(&mut self, k: KeyEvent) -> Action {
        if k.modifiers.contains(KeyModifiers::CONTROL) && k.code == KeyCode::Char('c') {
            return Action::Quit;
        }
        if self.editing {
            match k.code {
                KeyCode::Char(c) => self.filter.push(c),
                KeyCode::Backspace => {
                    self.filter.pop();
                }
                KeyCode::Enter => self.editing = false,
                KeyCode::Esc => {
                    self.filter.clear();
                    self.editing = false;
                }
                _ => {}
            }
            self.selected_entry = 0;
            return Action::None;
        }
        if self.links.is_some() {
            return self.links_key(k);
        }
        match k.code {
            KeyCode::Char('q') | KeyCode::Esc => return Action::Quit,
            KeyCode::Tab => {
                self.focus = if self.focus == Pane::Groups { Pane::Repos } else { Pane::Groups };
            }
            KeyCode::Char('/') => {
                self.editing = true;
                self.status.clear();
            }
            KeyCode::Char('r') if !self.refreshing => return Action::Refresh,
            KeyCode::Up | KeyCode::Char('k') => self.move_by(-1),
            KeyCode::Down | KeyCode::Char('j') => self.move_by(1),
            KeyCode::Right
                if self.focus == Pane::Groups && self.node(&self.selected_node).is_some_and(|n| !n.children.is_empty()) =>
            {
                self.expanded.insert(self.selected_node.clone());
            }
            KeyCode::Left if self.focus == Pane::Repos => self.focus = Pane::Groups,
            // replie, ou remonte au parent si deja replie
            KeyCode::Left if !self.expanded.remove(&self.selected_node) && self.selected_node.len() > 1 => {
                self.selected_node.pop();
                self.selected_entry = 0;
            }
            KeyCode::Enter if self.focus == Pane::Groups => self.focus = Pane::Repos,
            KeyCode::Enter => return self.go_to(),
            KeyCode::Char('c') => return self.clone_key(),
            KeyCode::Char('C') => {
                if self.missing_under_selected().is_empty() {
                    self.status = "rien à cloner ici".into();
                } else {
                    return Action::PickMissing;
                }
            }
            KeyCode::Char('o') => {
                match self.current().and_then(|i| self.tree.entries[i].web_url.clone()) {
                    Some(u) => return Action::OpenWeb(u),
                    None => self.status = "pas de page GitLab connue".into(),
                }
            }
            KeyCode::Char('l') => self.open_links(),
            _ => {}
        }
        Action::None
    }

    fn move_by(&mut self, d: isize) {
        let step = |pos: usize, len: usize| (pos as isize + d).clamp(0, len.saturating_sub(1) as isize) as usize;
        if self.focus == Pane::Repos {
            self.selected_entry = step(self.selected_entry, self.visible_entries().len());
            return;
        }
        let rows = self.rows();
        if rows.is_empty() {
            return;
        }
        // noeud masque par le filtre : on repart du haut
        let pos = rows.iter().position(|(p, _)| *p == self.selected_node).map_or(0, |p| step(p, rows.len()));
        self.selected_node = rows[pos].0.clone();
        self.selected_entry = 0;
    }

    fn go_to(&mut self) -> Action {
        let Some(i) = self.current() else { return Action::None };
        match &self.tree.entries[i].local {
            Some(d) => Action::GoTo(d.clone()),
            None => {
                self.status = NOT_CLONED.into();
                Action::None
            }
        }
    }

    fn clone_key(&mut self) -> Action {
        let Some(i) = self.current() else { return Action::None };
        let e = &self.tree.entries[i];
        if e.local.is_some() {
            self.status = "déjà cloné".into();
        } else if e.clone_url.is_none() {
            self.status = "pas d'URL de clone".into();
        } else if self.cloning.get(&i).map(String::as_str) != Some(CLONING) {
            return Action::Clone(vec![i]);
        }
        Action::None
    }

    /// Marque les clones a lancer : (chemin, url, destination).
    pub fn start_clone(&mut self, ids: &[usize]) -> Vec<(String, String, PathBuf)> {
        let mut jobs = Vec::new();
        for &i in ids {
            let e = &self.tree.entries[i];
            let (None, Some(url)) = (&e.local, &e.clone_url) else { continue };
            if self.cloning.get(&i).map(String::as_str) == Some(CLONING) {
                continue;
            }
            jobs.push((e.path.clone(), url.clone(), self.settings.work_dir.join(&e.path)));
            self.cloning.insert(i, CLONING.into());
        }
        jobs
    }

    /// Resultat d'un clone, retrouve par chemin : l'arbre a pu etre reconstruit entre-temps.
    pub fn clone_done(&mut self, path: &str, res: Result<PathBuf, String>) {
        let Some(i) = self.tree.entries.iter().position(|e| e.path == path) else { return };
        match res {
            Ok(d) => {
                let e = &mut self.tree.entries[i];
                e.local = Some(d);
                e.misplaced = false;
                self.cloning.remove(&i);
            }
            Err(e) => {
                self.cloning.insert(i, format!("échec : {e}"));
            }
        }
    }

    /// Repos clones affiches dont l'etat git n'a pas encore ete demande.
    pub fn state_requests(&mut self) -> Vec<(usize, PathBuf)> {
        let mut out = Vec::new();
        for i in self.visible_entries() {
            if let Some(d) = &self.tree.entries[i].local {
                if self.asked.insert(i) {
                    out.push((i, d.clone()));
                }
            }
        }
        out
    }

    pub fn set_tree(&mut self, tree: Tree, fetched_at: i64) {
        self.tree = tree;
        self.fetched_at = Some(fetched_at);
        self.refreshing = false;
        self.generation += 1;
        self.states.clear();
        self.asked.clear();
        self.cloning.clear();
        self.links = None;
        if self.node(&self.selected_node).is_none() {
            self.selected_node = vec![0];
        }
        self.selected_entry = 0;
    }

    pub fn index_line(&self, now: i64) -> String {
        if self.refreshing {
            return "rafraîchissement de l'index…".into();
        }
        match self.fetched_at {
            None => "index en cours de construction — r pour rafraîchir".into(),
            Some(t) if now - t < 3_600 => format!("index : il y a {} min", (now - t).max(0) / 60),
            Some(t) => format!("index : il y a {} h", (now - t) / 3_600),
        }
    }

    /// Groupe d'application d'un chemin (segment app_segment + nom), pour la config commune.
    fn app_group(&self, path: &str) -> Option<String> {
        let seg = self.settings.app_segment.as_deref()?;
        let segs: Vec<&str> = path.split('/').collect();
        let k = segs.iter().position(|s| *s == seg)?;
        (k + 2 < segs.len()).then(|| segs[..k + 2].join("/"))
    }

    fn open_links(&mut self) {
        let Some(i) = self.current() else { return };
        let e = &self.tree.entries[i];
        let mut ls = links::links_for(e, &self.settings);
        if let Some(g) = self.app_group(&e.path) {
            ls.extend(links::common_for(&g, &self.settings));
        }
        let mut rows: Vec<LinkRow> = Vec::new();
        let mut dead = false;
        for l in ls {
            let Some(t) = self.tree.entries.iter().position(|e| e.path == l.target) else {
                dead = true;
                continue;
            };
            let mut text = format!("{:<8}{}", kind_label(l.kind), l.target);
            if let Some(r) = &l.git_ref {
                text.push_str(&format!(" @{r}"));
            }
            if l.assumed {
                text.push_str(" (supposé)");
            }
            rows.push(LinkRow { text, target: Some(t) });
        }
        if dead {
            rows.push(LinkRow { text: "pas de config trouvée".into(), target: None });
        }
        if rows.is_empty() {
            self.status = "aucun lien".into();
            return;
        }
        self.links = Some(rows);
        self.link_sel = 0;
    }

    fn links_key(&mut self, k: KeyEvent) -> Action {
        let n = self.links.as_ref().map_or(0, Vec::len);
        match k.code {
            KeyCode::Esc | KeyCode::Char('q') | KeyCode::Char('l') => self.links = None,
            KeyCode::Up | KeyCode::Char('k') => self.link_sel = self.link_sel.saturating_sub(1),
            KeyCode::Down | KeyCode::Char('j') => self.link_sel = (self.link_sel + 1).min(n.saturating_sub(1)),
            KeyCode::Enter => {
                let target = self.links.as_ref().and_then(|l| l.get(self.link_sel)).and_then(|r| r.target);
                let Some(t) = target else { return Action::None };
                self.links = None;
                if let Some(d) = &self.tree.entries[t].local {
                    return Action::GoTo(d.clone());
                }
                self.reveal(t);
                self.status = NOT_CLONED.into();
            }
            _ => {}
        }
        Action::None
    }

    /// Selectionne l'entree `t` : son noeud deplie, filtre retire.
    fn reveal(&mut self, t: usize) {
        fn find(n: &Node, t: usize, p: &mut Vec<usize>) -> bool {
            if n.entries.contains(&t) {
                return true;
            }
            for (i, c) in n.children.iter().enumerate() {
                p.push(i);
                if find(c, t, p) {
                    return true;
                }
                p.pop();
            }
            false
        }
        let mut p = vec![0];
        if !find(&self.tree.gitlab, t, &mut p) {
            p = vec![1];
            if !find(&self.tree.outside, t, &mut p) {
                return;
            }
        }
        self.filter.clear();
        (1..p.len()).for_each(|k| {
            self.expanded.insert(p[..k].to_vec());
        });
        self.selected_node = p;
        self.focus = Pane::Repos;
        self.selected_entry = self.visible_entries().iter().position(|&i| i == t).unwrap_or(0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::index::{AppMeta, Index, IndexProject};
    use super::super::local::LocalRepo;
    use super::super::remote::Remote;
    use super::super::tree;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
    use std::collections::BTreeMap;
    use std::path::Path;

    fn settings() -> Settings {
        let mut s = Settings::load(Path::new("/nonexistent/projects.toml"));
        s.ptf_root = Some("plat".into());
        s.app_segment = Some("apps".into());
        s.bus = BTreeMap::from([("bu1".to_string(), String::new())]);
        s.app_var_keys = vec!["APP_NAME".into(), "APP_ID".into()];
        s.work_dir = PathBuf::from("/w");
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

    const API: &str = "plat/bu1/apps/shop/components/api";
    const CFG: &str = "plat/bu1/apps/shop/configurations/api";
    const WEB: &str = "plat/bu1/apps/cart/components/web";

    fn app() -> App {
        let idx = Index {
            fetched_at: 0,
            projects: [API, CFG, WEB, "shared/lib/x"].iter().map(|p| proj(p)).collect(),
            apps: vec![AppMeta {
                group: "plat/bu1/apps/shop".into(),
                vars: BTreeMap::from([
                    ("APP_NAME".to_string(), "Store".to_string()),
                    ("APP_ID".to_string(), "A1".to_string()),
                ]),
            }],
        };
        let locals = [LocalRepo { dir: PathBuf::from("/w").join(API), rel: API.into(), remote: Remote::Gitlab(API.into()) }];
        let s = settings();
        App::new(tree::build(Some(&idx), &locals, &s), Arc::new(s), Some(0))
    }

    fn key(c: KeyCode) -> KeyEvent {
        KeyEvent::new(c, KeyModifiers::NONE)
    }

    fn typed(a: &mut App, s: &str) {
        s.chars().for_each(|c| {
            a.handle_key(key(KeyCode::Char(c)));
        });
    }

    fn paths(a: &App) -> Vec<&str> {
        a.visible_entries().iter().map(|&i| a.tree.entries[i].path.as_str()).collect()
    }

    /// chemin du noeud libelle `label` dans l'arbre GitLab
    fn node_path(a: &App, label: &str) -> Vec<usize> {
        fn walk(n: &tree::Node, label: &str, p: &mut Vec<usize>) -> bool {
            if n.label == label {
                return true;
            }
            for (i, c) in n.children.iter().enumerate() {
                p.push(i);
                if walk(c, label, p) {
                    return true;
                }
                p.pop();
            }
            false
        }
        let mut p = vec![0];
        assert!(walk(&a.tree.gitlab, label, &mut p), "{label}");
        p
    }

    fn select(a: &mut App, path: &str) {
        a.focus = Pane::Repos;
        a.selected_entry = a.visible_entries().iter().position(|&i| a.tree.entries[i].path == path).unwrap();
    }

    #[test]
    fn entree_va_au_repo_clone() {
        let mut a = app();
        select(&mut a, API);
        assert_eq!(a.handle_key(key(KeyCode::Enter)), Action::GoTo(PathBuf::from("/w").join(API)));
        select(&mut a, WEB);
        assert_eq!(a.handle_key(key(KeyCode::Enter)), Action::None);
        assert!(a.status.contains("c "), "{}", a.status);
    }

    #[test]
    fn filtre_sur_chemin_et_libelle() {
        let mut a = app();
        typed(&mut a, "/shop");
        a.handle_key(key(KeyCode::Enter));
        assert_eq!(paths(&a), [API, CFG]);
        // le filtre ne capte plus les touches : q quitte
        assert_eq!(a.handle_key(key(KeyCode::Char('q'))), Action::Quit);
        let mut a = app();
        typed(&mut a, "/a1");
        assert_eq!(paths(&a), [API, CFG]);
        // les noeuds sans resultat disparaissent de l'arbre
        let labels: Vec<String> = a.rows().iter().map(|(p, _)| a.node(p).unwrap().label.clone()).collect();
        assert!(labels.contains(&"Store · A1".to_string()) && !labels.contains(&"cart".to_string()), "{labels:?}");
    }

    #[test]
    fn manquants_du_sous_arbre() {
        let mut a = app();
        a.selected_node = node_path(&a, "Store · A1");
        assert_eq!(paths(&a), [API, CFG]);
        let missing: Vec<&str> = a.missing_under_selected().iter().map(|&i| a.tree.entries[i].path.as_str()).collect();
        assert_eq!(missing, [CFG]);
        assert_eq!(a.handle_key(key(KeyCode::Char('C'))), Action::PickMissing);
    }

    #[test]
    fn tab_alterne() {
        let mut a = app();
        assert_eq!(a.focus, Pane::Groups);
        a.handle_key(key(KeyCode::Tab));
        assert_eq!(a.focus, Pane::Repos);
        a.handle_key(key(KeyCode::Tab));
        assert_eq!(a.focus, Pane::Groups);
    }

    #[test]
    fn clone_puis_etat() {
        let mut a = app();
        select(&mut a, CFG);
        let i = a.visible_entries()[a.selected_entry];
        assert_eq!(a.handle_key(key(KeyCode::Char('c'))), Action::Clone(vec![i]));
        let jobs = a.start_clone(&[i]);
        assert_eq!(jobs, [(CFG.to_string(), format!("https://h.example/{CFG}.git"), PathBuf::from("/w").join(CFG))]);
        // deja en cours : pas de second job
        assert!(a.start_clone(&[i]).is_empty());
        a.clone_done(CFG, Err("fatal: x".into()));
        assert_eq!(a.cloning[&i], "échec : fatal: x");
        a.clone_done(CFG, Ok(PathBuf::from("/w").join(CFG)));
        assert!(a.tree.entries[i].local.is_some() && !a.cloning.contains_key(&i));
        // les etats git sont demandes une seule fois par repo clone visible
        let asked: Vec<usize> = a.state_requests().into_iter().map(|(i, _)| i).collect();
        assert_eq!(asked.len(), 2);
        assert!(a.state_requests().is_empty());
    }

    #[test]
    fn roles_et_age() {
        assert_eq!([role(Some(50)), role(Some(40)), role(Some(30)), role(Some(20)), role(None)], ["O", "M", "D", " ", " "]);
        let mut a = app();
        assert_eq!(a.index_line(7_200), "index : il y a 2 h");
        a.fetched_at = None;
        assert_eq!(a.index_line(0), "index en cours de construction — r pour rafraîchir");
    }

    #[test]
    fn liens_existants_et_absents() {
        let mut s = settings();
        s.config_rules = vec![super::super::settings::Rule {
            from: regex::Regex::new("^(.+)/components/(.+)$").unwrap(),
            to: "$1/configurations/$2".into(),
        }];
        s.common_configs = vec!["configuration/shared".into()];
        let mut a = app();
        a.settings = Arc::new(s);
        select(&mut a, WEB);
        a.handle_key(key(KeyCode::Char('l')));
        let texts: Vec<&str> = a.links.as_ref().unwrap().iter().map(|r| r.text.as_str()).collect();
        assert_eq!(texts, ["pas de config trouvée"]);
        a.handle_key(key(KeyCode::Esc));
        assert!(a.links.is_none());
        // lien vers un repo non clone : Entree le selectionne et invite a cloner
        a.selected_node = vec![0];
        select(&mut a, API);
        a.handle_key(key(KeyCode::Char('l')));
        let rows = a.links.as_ref().unwrap();
        assert_eq!(rows[0].text, format!("config  {CFG} (supposé)"));
        assert_eq!(a.handle_key(key(KeyCode::Enter)), Action::None);
        assert_eq!(a.tree.entries[a.visible_entries()[a.selected_entry]].path, CFG);
        assert!(a.status.contains("c "), "{}", a.status);
    }
}
