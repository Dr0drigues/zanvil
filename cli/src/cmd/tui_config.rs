use crate::config;
use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    prelude::CrosstermBackend,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph, Tabs},
    Terminal,
};
use std::fs;
use std::io;

// =============================================================================
// App state
// =============================================================================
struct App {
    active_tab: usize,
    tabs: Vec<&'static str>,
    // Modules
    modules: Vec<ModuleItem>,
    module_state: ListState,
    // Themes
    themes: Vec<String>,
    theme_state: ListState,
    current_theme: String,
    // Auto-update
    au_enabled: bool,
    au_frequency: u32,
    au_mode: String,
    au_selected: usize,
    // Dirty flag
    dirty: bool,
}

struct ModuleItem {
    name: String,
    enabled: bool,
}

impl App {
    fn new() -> Self {
        let config_content = config::read_config().unwrap_or_default();
        let zanvil_dir = config::zanvil_dir();

        // Parse modules
        let parsed = config::parse_modules(&config_content);
        let modules: Vec<ModuleItem> = parsed
            .into_iter()
            .map(|m| ModuleItem {
                name: m.name.clone(),
                enabled: m.enabled,
            })
            .collect();

        // Parse themes
        let themes_dir = zanvil_dir.join("config").join("themes");
        let mut themes: Vec<String> = Vec::new();
        if let Ok(entries) = fs::read_dir(&themes_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() && path.join("prompt.toml").exists() {
                    themes.push(entry.file_name().to_string_lossy().to_string());
                } else if path.extension().map_or(false, |e| e == "toml") {
                    let name = path.file_stem().unwrap().to_string_lossy().to_string();
                    if !themes.contains(&name) {
                        themes.push(name);
                    }
                }
            }
        }
        themes.sort();

        // Current theme
        let current_theme = fs::read_to_string(zanvil_dir.join(".current_theme"))
            .unwrap_or_else(|_| "default".to_string())
            .trim()
            .to_string();

        // Auto-update
        let au_enabled = extract_bool(&config_content, "ZANVIL_AUTO_UPDATE", true);
        let au_frequency: u32 = extract_value(&config_content, "ZANVIL_UPDATE_FREQUENCY")
            .parse()
            .unwrap_or(7);
        let au_mode = extract_value(&config_content, "ZANVIL_UPDATE_MODE")
            .trim_matches('"')
            .to_string();

        let mut module_state = ListState::default();
        if !modules.is_empty() {
            module_state.select(Some(0));
        }
        let mut theme_state = ListState::default();
        let theme_idx = themes.iter().position(|t| t == &current_theme).unwrap_or(0);
        theme_state.select(Some(theme_idx));

        App {
            active_tab: 0,
            tabs: vec!["Modules", "Themes", "Auto-Update"],
            modules,
            module_state,
            themes,
            theme_state,
            current_theme,
            au_enabled,
            au_frequency,
            au_mode: if au_mode.is_empty() {
                "prompt".to_string()
            } else {
                au_mode
            },
            au_selected: 0,
            dirty: false,
        }
    }

    fn save(&self) {
        let mut content = config::read_config().unwrap_or_default();

        // Save modules
        for module in &self.modules {
            if let Ok(new) = config::set_module(&content, &module.name, module.enabled) {
                content = new;
            }
        }

        // Save auto-update settings
        content = set_config_value(&content, "ZANVIL_AUTO_UPDATE", &self.au_enabled.to_string());
        content = set_config_value(
            &content,
            "ZANVIL_UPDATE_FREQUENCY",
            &self.au_frequency.to_string(),
        );
        content = set_config_value(
            &content,
            "ZANVIL_UPDATE_MODE",
            &format!("\"{}\"", self.au_mode),
        );

        let _ = config::write_config(&content);

        // Save theme
        let _ = fs::write(
            config::zanvil_dir().join(".current_theme"),
            &self.current_theme,
        );
    }
}

// =============================================================================
// Main entry point
// =============================================================================
pub fn run() {
    enable_raw_mode().expect("Failed to enable raw mode");
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen).expect("Failed to enter alternate screen");
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend).expect("Failed to create terminal");

    let mut app = App::new();
    let result = run_app(&mut terminal, &mut app);

    disable_raw_mode().expect("Failed to disable raw mode");
    execute!(terminal.backend_mut(), LeaveAlternateScreen)
        .expect("Failed to leave alternate screen");

    if let Err(e) = result {
        eprintln!("Error: {}", e);
    }

    if app.dirty {
        app.save();
        println!("✓ Configuration sauvegardee. Rechargez avec: ss");
    }
}

fn run_app(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &mut App,
) -> io::Result<()> {
    loop {
        terminal.draw(|f| ui(f, app))?;

        if let Event::Key(key) = event::read()? {
            if key.kind != KeyEventKind::Press {
                continue;
            }
            match key.code {
                KeyCode::Char('q') | KeyCode::Esc => return Ok(()),
                KeyCode::Tab => {
                    app.active_tab = (app.active_tab + 1) % app.tabs.len();
                }
                KeyCode::BackTab => {
                    app.active_tab = if app.active_tab == 0 {
                        app.tabs.len() - 1
                    } else {
                        app.active_tab - 1
                    };
                }
                KeyCode::Up | KeyCode::Char('k') => match app.active_tab {
                    0 => list_prev(&mut app.module_state, app.modules.len()),
                    1 => list_prev(&mut app.theme_state, app.themes.len()),
                    2 => {
                        if app.au_selected > 0 {
                            app.au_selected -= 1;
                        }
                    }
                    _ => {}
                },
                KeyCode::Down | KeyCode::Char('j') => match app.active_tab {
                    0 => list_next(&mut app.module_state, app.modules.len()),
                    1 => list_next(&mut app.theme_state, app.themes.len()),
                    2 => {
                        if app.au_selected < 2 {
                            app.au_selected += 1;
                        }
                    }
                    _ => {}
                },
                KeyCode::Char(' ') | KeyCode::Enter => match app.active_tab {
                    0 => {
                        if let Some(i) = app.module_state.selected() {
                            app.modules[i].enabled = !app.modules[i].enabled;
                            app.dirty = true;
                        }
                    }
                    1 => {
                        if let Some(i) = app.theme_state.selected() {
                            app.current_theme = app.themes[i].clone();
                            app.dirty = true;
                        }
                    }
                    2 => {
                        match app.au_selected {
                            0 => {
                                app.au_enabled = !app.au_enabled;
                                app.dirty = true;
                            }
                            1 => {
                                // Cycle frequency: 1 -> 3 -> 7 -> 14 -> 30 -> 1
                                app.au_frequency = match app.au_frequency {
                                    1 => 3,
                                    3 => 7,
                                    7 => 14,
                                    14 => 30,
                                    _ => 1,
                                };
                                app.dirty = true;
                            }
                            2 => {
                                // Toggle mode
                                app.au_mode = if app.au_mode == "prompt" {
                                    "auto".to_string()
                                } else {
                                    "prompt".to_string()
                                };
                                app.dirty = true;
                            }
                            _ => {}
                        }
                    }
                    _ => {}
                },
                _ => {}
            }
        }
    }
}

// =============================================================================
// UI rendering
// =============================================================================
fn ui(f: &mut ratatui::Frame, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Tabs
            Constraint::Min(1),   // Content
            Constraint::Length(2), // Help bar
        ])
        .split(f.area());

    // Tabs
    let tab_titles: Vec<Line> = app.tabs.iter().map(|t| Line::from(*t)).collect();
    let tabs = Tabs::new(tab_titles)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(" zanvil config "),
        )
        .select(app.active_tab)
        .highlight_style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        );
    f.render_widget(tabs, chunks[0]);

    // Content
    match app.active_tab {
        0 => render_modules(f, app, chunks[1]),
        1 => render_themes(f, app, chunks[1]),
        2 => render_auto_update(f, app, chunks[1]),
        _ => {}
    }

    // Help bar
    let dirty_marker = if app.dirty { " [modifie]" } else { "" };
    let help = Paragraph::new(Line::from(vec![
        Span::styled(" ↑↓ ", Style::default().fg(Color::Cyan)),
        Span::raw("naviguer  "),
        Span::styled("Space/Enter ", Style::default().fg(Color::Cyan)),
        Span::raw("toggle  "),
        Span::styled("Tab ", Style::default().fg(Color::Cyan)),
        Span::raw("onglet  "),
        Span::styled("q ", Style::default().fg(Color::Cyan)),
        Span::raw("quitter"),
        Span::styled(dirty_marker, Style::default().fg(Color::Yellow)),
    ]));
    f.render_widget(help, chunks[2]);
}

fn render_modules(f: &mut ratatui::Frame, app: &App, area: Rect) {
    let items: Vec<ListItem> = app
        .modules
        .iter()
        .map(|m| {
            let symbol = if m.enabled { "✓" } else { "✗" };
            let style = if m.enabled {
                Style::default().fg(Color::Green)
            } else {
                Style::default().fg(Color::DarkGray)
            };
            ListItem::new(Line::from(vec![
                Span::styled(format!(" {} ", symbol), style),
                Span::styled(
                    format!("ZANVIL_MODULE_{}", m.name),
                    if m.enabled {
                        Style::default()
                    } else {
                        Style::default().fg(Color::DarkGray)
                    },
                ),
            ]))
        })
        .collect();

    let list = List::new(items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(" Modules (Space pour toggle) "),
        )
        .highlight_style(
            Style::default()
                .bg(Color::DarkGray)
                .add_modifier(Modifier::BOLD),
        );

    f.render_stateful_widget(list, area, &mut app.module_state.clone());
}

fn render_themes(f: &mut ratatui::Frame, app: &App, area: Rect) {
    let items: Vec<ListItem> = app
        .themes
        .iter()
        .map(|t| {
            let is_current = *t == app.current_theme;
            let symbol = if is_current { "●" } else { "○" };
            let style = if is_current {
                Style::default()
                    .fg(Color::Cyan)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default()
            };
            ListItem::new(Line::from(vec![
                Span::styled(format!(" {} ", symbol), style),
                Span::styled(t.clone(), style),
                if is_current {
                    Span::styled(" (actif)", Style::default().fg(Color::Green))
                } else {
                    Span::raw("")
                },
            ]))
        })
        .collect();

    let list = List::new(items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(" Themes (Enter pour appliquer) "),
        )
        .highlight_style(
            Style::default()
                .bg(Color::DarkGray)
                .add_modifier(Modifier::BOLD),
        );

    f.render_stateful_widget(list, area, &mut app.theme_state.clone());
}

fn render_auto_update(f: &mut ratatui::Frame, app: &App, area: Rect) {
    let freq_str = format!("{} jour(s)", app.au_frequency);
    let enabled_str = if app.au_enabled { "oui" } else { "non" };
    let settings: Vec<(&str, &str)> = vec![
        ("Active", enabled_str),
        ("Frequence", &freq_str),
        ("Mode", &app.au_mode),
    ];

    let items: Vec<ListItem> = settings
        .iter()
        .enumerate()
        .map(|(i, (label, value))| {
            let selected = i == app.au_selected;
            let arrow = if selected { "▸" } else { " " };
            ListItem::new(Line::from(vec![
                Span::styled(
                    format!(" {} ", arrow),
                    Style::default().fg(Color::Cyan),
                ),
                Span::styled(
                    format!("{:<16}", label),
                    Style::default().add_modifier(Modifier::BOLD),
                ),
                Span::styled(
                    value.to_string(),
                    Style::default().fg(Color::Yellow),
                ),
            ]))
        })
        .collect();

    let list = List::new(items).block(
        Block::default()
            .borders(Borders::ALL)
            .title(" Auto-Update (Space pour modifier) "),
    );

    f.render_widget(list, area);
}

// =============================================================================
// Helpers
// =============================================================================
fn list_next(state: &mut ListState, len: usize) {
    if len == 0 {
        return;
    }
    let i = state.selected().map_or(0, |i| (i + 1) % len);
    state.select(Some(i));
}

fn list_prev(state: &mut ListState, len: usize) {
    if len == 0 {
        return;
    }
    let i = state
        .selected()
        .map_or(0, |i| if i == 0 { len - 1 } else { i - 1 });
    state.select(Some(i));
}

fn extract_value(content: &str, key: &str) -> String {
    content
        .lines()
        .find(|l| l.trim().starts_with(&format!("{}=", key)))
        .and_then(|l| l.split('=').nth(1))
        .map(|v| v.trim().to_string())
        .unwrap_or_default()
}

fn extract_bool(content: &str, key: &str, default: bool) -> bool {
    let val = extract_value(content, key);
    if val.is_empty() {
        default
    } else {
        val == "true"
    }
}

fn set_config_value(content: &str, key: &str, value: &str) -> String {
    let target = format!("{}=", key);
    let replacement = format!("{}={}", key, value);
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

    let mut result = lines.join("\n");
    if !found {
        result.push('\n');
        result.push_str(&replacement);
    }
    if content.ends_with('\n') && !result.ends_with('\n') {
        result.push('\n');
    }
    result
}
