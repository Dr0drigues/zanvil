// Terminal de l'explorateur : boucle d'evenements, travaux en arriere-plan, rendu.
// Etats git et clones tournent dans des threads ; l'UI ne fait qu'attendre des messages.
use super::app::{role, Action, App, Pane};
use super::git::{self, GitState};
use super::index::{self, Index};
use super::local::{self, LocalRepo};
use super::tree;
use crossterm::{
    event::{self, Event, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    layout::{Constraint, Layout},
    prelude::CrosstermBackend,
    style::{Color, Modifier, Style},
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph},
    Frame, Terminal,
};
use std::collections::HashSet;
use std::io::{self, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

type Term = Terminal<CrosstermBackend<io::Stdout>>;
type Job = Box<dyn FnOnce() -> Msg + Send>;

enum Msg {
    State(u64, usize, Option<GitState>),
    Cloned(String, Result<PathBuf, String>),
    Refreshed(Result<(Index, Vec<LocalRepo>), String>),
}

const WORKERS: usize = 4;

fn enter() -> io::Result<()> {
    enable_raw_mode()?;
    execute!(io::stdout(), EnterAlternateScreen)
}

fn leave() {
    let _ = disable_raw_mode();
    let _ = execute!(io::stdout(), LeaveAlternateScreen);
}

/// `n` threads qui executent les travaux recus et renvoient leur message.
fn pool(n: usize, tx: &Sender<Msg>) -> Sender<Job> {
    let (jtx, jrx) = mpsc::channel::<Job>();
    let jrx = Arc::new(Mutex::new(jrx));
    for _ in 0..n {
        let (jrx, tx) = (Arc::clone(&jrx), tx.clone());
        thread::spawn(move || loop {
            let Ok(job) = jrx.lock().map_err(drop).and_then(|r| r.recv().map_err(drop)) else { return };
            if tx.send(job()).is_err() {
                return;
            }
        });
    }
    jtx
}

/// Lance l'interface ; rend le dossier choisi (Entree) ou None.
pub fn run(mut app: App) -> io::Result<Option<PathBuf>> {
    let prev = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        leave();
        prev(info);
    }));
    enter()?;
    let res = Terminal::new(CrosstermBackend::new(io::stdout())).and_then(|mut t| event_loop(&mut t, &mut app));
    leave();
    res
}

fn event_loop(term: &mut Term, app: &mut App) -> io::Result<Option<PathBuf>> {
    let (tx, rx) = mpsc::channel();
    let states = pool(WORKERS, &tx);
    let clones = pool(WORKERS, &tx);
    loop {
        let mut viewport = app.viewport;
        term.draw(|f| viewport = draw(f, app))?;
        // seulement les lignes a l'ecran, connues apres le rendu
        app.viewport = viewport;
        for (i, d) in app.state_requests() {
            let g = app.generation;
            let _ = states.send(Box::new(move || Msg::State(g, i, git::state(&d))));
        }
        if event::poll(Duration::from_millis(100))? {
            if let Event::Key(k) = event::read()? {
                if k.kind == KeyEventKind::Press {
                    match app.handle_key(k) {
                        Action::None => {}
                        Action::Quit => return Ok(None),
                        Action::GoTo(d) => return Ok(Some(d)),
                        Action::Clone(ids) => start_clones(app, &clones, &ids),
                        Action::PickMissing => pick_missing(term, app, &clones)?,
                        Action::OpenWeb(u) => open_web(app, &u),
                        Action::Refresh => refresh(app, &tx),
                    }
                }
            }
        }
        drain(app, &rx);
    }
}

fn drain(app: &mut App, rx: &Receiver<Msg>) {
    while let Ok(m) = rx.try_recv() {
        match m {
            Msg::State(g, i, st) => app.state_done(g, i, st),
            Msg::Cloned(path, res) => app.clone_done(&path, res),
            Msg::Refreshed(Ok((idx, locals))) => {
                let t = tree::build(Some(&idx), &locals, &app.settings);
                app.set_tree(t, idx.fetched_at);
                app.status = format!("index rafraîchi : {} projets", idx.projects.len());
            }
            Msg::Refreshed(Err(e)) => {
                app.refreshing = false;
                app.status = e;
            }
        }
    }
}

fn start_clones(app: &mut App, pool: &Sender<Job>, ids: &[usize]) {
    for (path, url, dest) in app.start_clone(ids) {
        let _ = pool.send(Box::new(move || {
            let res = git::clone(&url, &dest).map(|_| dest);
            Msg::Cloned(path, res)
        }));
    }
}

/// `C` : fzf hors de l'ecran alternatif, tout preselectionne, puis clone des choix.
fn pick_missing(term: &mut Term, app: &mut App, pool: &Sender<Job>) -> io::Result<()> {
    let missing = app.missing_under_selected();
    let list: Vec<&str> = missing.iter().map(|&i| app.tree.entries[i].path.as_str()).collect();
    let input = list.join("\n");
    leave();
    let res = Command::new("fzf")
        .args(["--multi", "--bind", "start:select-all"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .and_then(|mut c| {
            c.stdin.take().map_or(Ok(()), |mut s| s.write_all(input.as_bytes()))?;
            c.wait_with_output()
        });
    enter()?;
    term.clear()?;
    match res {
        Err(e) if e.kind() == io::ErrorKind::NotFound => app.status = "fzf introuvable : C indisponible".into(),
        Err(e) => app.status = format!("fzf : {e}"),
        Ok(o) => {
            let out = String::from_utf8_lossy(&o.stdout);
            let chosen: HashSet<&str> = out.lines().collect();
            let ids: Vec<usize> =
                missing.into_iter().filter(|&i| chosen.contains(app.tree.entries[i].path.as_str())).collect();
            start_clones(app, pool, &ids);
        }
    }
    Ok(())
}

fn open_web(app: &mut App, url: &str) {
    let opener = if cfg!(target_os = "macos") { "open" } else { "xdg-open" };
    let res = Command::new(opener).arg(url).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn();
    if let Err(e) = res {
        app.status = format!("{opener} : {e}");
    }
}

fn refresh(app: &mut App, tx: &Sender<Msg>) {
    app.refreshing = true;
    app.status.clear();
    let (s, tx) = (Arc::clone(&app.settings), tx.clone());
    thread::spawn(move || {
        let res = index::refresh(&s)
            .and_then(|idx| index::write_cache(&index::cache_path(), &idx).map(|_| idx).map_err(|e| e.to_string()))
            .map(|idx| (idx, local::scan(&s.work_dir, &s.gitlab_host)));
        let _ = tx.send(Msg::Refreshed(res));
    });
}

fn pane(title: String, focused: bool) -> Block<'static> {
    let style = if focused { Style::default().fg(Color::Cyan) } else { Style::default().fg(Color::DarkGray) };
    Block::default().borders(Borders::ALL).border_style(style).title(title)
}

fn highlight(focused: bool) -> Style {
    if focused {
        Style::default().add_modifier(Modifier::REVERSED)
    } else {
        Style::default().add_modifier(Modifier::BOLD)
    }
}

fn entry_line(app: &App, i: usize, key: &str) -> String {
    let e = &app.tree.entries[i];
    let rel = e.path.strip_prefix(key).and_then(|r| r.strip_prefix('/')).filter(|_| !key.is_empty());
    let mut s = format!("{} {} {}", if e.local.is_some() { "●" } else { "○" }, role(e.access), rel.unwrap_or(&e.path));
    if e.misplaced {
        s.push_str("  cloné ailleurs");
    }
    if e.empty {
        s.push_str("  vide");
    }
    if let Some(st) = app.states.get(&i) {
        s.push_str(&format!("  {}", st.branch));
        if st.dirty {
            s.push_str(" modifié");
        }
        if st.ahead > 0 {
            s.push_str(&format!(" ↑{}", st.ahead));
        }
        if st.behind > 0 {
            s.push_str(&format!(" ↓{} en retard", st.behind));
        }
        if !st.dirty && st.ahead == 0 && st.behind == 0 {
            s.push_str(" propre");
        }
    }
    if let Some(c) = app.cloning.get(&i) {
        s.push_str(&format!("  {c}"));
    }
    s
}

/// Rend aussi la fenetre visible du panneau de droite (debut, nombre de lignes).
fn draw(f: &mut Frame, app: &App) -> (usize, usize) {
    let [main, bottom] = Layout::vertical([Constraint::Min(1), Constraint::Length(1)]).areas(f.area());
    let [left, right] = Layout::horizontal([Constraint::Percentage(35), Constraint::Percentage(65)]).areas(main);

    let rows = app.rows();
    let items: Vec<ListItem> = rows
        .iter()
        .filter_map(|(p, depth)| {
            let n = app.node(p)?;
            let mark = if n.children.is_empty() { " " } else if app.is_open(p) { "▾" } else { "▸" };
            Some(ListItem::new(format!("{}{mark} {}", "  ".repeat(*depth), n.label)))
        })
        .collect();
    let mut st = ListState::default().with_selected(rows.iter().position(|(p, _)| *p == app.selected_node));
    let groups = app.focus == Pane::Groups;
    let list = List::new(items).block(pane("Groupes".into(), groups)).highlight_style(highlight(groups));
    f.render_stateful_widget(list, left, &mut st);

    let repos = app.focus == Pane::Repos;
    let mut viewport = app.viewport;
    if let Some(links) = &app.links {
        let items: Vec<ListItem> = links.iter().map(|l| ListItem::new(l.text.clone())).collect();
        let mut st = ListState::default().with_selected(Some(app.link_sel));
        let title = "Liens — Entrée y aller, Échap fermer".to_string();
        f.render_stateful_widget(List::new(items).block(pane(title, true)).highlight_style(highlight(true)), right, &mut st);
    } else {
        let key = app.node(&app.selected_node).map_or("", |n| n.key.as_str());
        let visible = app.visible_entries();
        let items: Vec<ListItem> = visible
            .iter()
            .map(|&i| {
                let dim = app.tree.entries[i].local.is_none();
                let style = if dim { Style::default().fg(Color::DarkGray) } else { Style::default() };
                ListItem::new(entry_line(app, i, key)).style(style)
            })
            .collect();
        let mut st = ListState::default().with_selected((!visible.is_empty()).then_some(app.selected_entry));
        let title = format!("Repos ({})", visible.len());
        f.render_stateful_widget(List::new(items).block(pane(title, repos)).highlight_style(highlight(repos)), right, &mut st);
        viewport = (st.offset(), right.height.saturating_sub(2) as usize);
    }

    let now = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs() as i64);
    let text = if app.editing {
        format!("/{}▏  Entrée valider, Échap effacer", app.filter)
    } else {
        let tail = if app.status.is_empty() {
            "Tab ↑↓ ←→ · Entrée y aller · c/C cloner · l liens · o GitLab · r rafraîchir · / filtrer · q quitter"
        } else {
            app.status.as_str()
        };
        let filter = if app.filter.is_empty() { String::new() } else { format!("  filtre : {}", app.filter) };
        format!("{}{filter}  │  {tail}", app.index_line(now))
    };
    f.render_widget(Paragraph::new(text), bottom);
    viewport
}
