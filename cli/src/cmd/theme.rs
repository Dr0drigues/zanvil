use clap::Subcommand;
use colored::Colorize;
use std::fs;
use std::path::PathBuf;

#[derive(Subcommand)]
pub enum ThemeAction {
    /// List available themes
    List,
    /// Apply a theme
    Apply {
        /// Theme name to apply
        name: String,
    },
    /// Show current theme
    Current,
}

fn zsh_env_dir() -> PathBuf {
    std::env::var("ZSH_ENV_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            dirs_fallback().join(".zsh_env")
        })
}

fn dirs_fallback() -> PathBuf {
    std::env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
}

fn themes_dir() -> PathBuf {
    zsh_env_dir().join("themes")
}

fn current_theme_file() -> PathBuf {
    zsh_env_dir().join(".current_theme")
}

fn starship_config() -> PathBuf {
    dirs_fallback()
        .join(".config")
        .join("starship.toml")
}

fn read_current_theme() -> Option<String> {
    fs::read_to_string(current_theme_file())
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

fn extract_description(path: &PathBuf) -> Option<String> {
    let content = fs::read_to_string(path).ok()?;
    for line in content.lines() {
        if let Some(desc) = line.strip_prefix("# Starship Theme:") {
            return Some(desc.trim().to_string());
        }
    }
    None
}

fn list_themes() {
    let dir = themes_dir();
    if !dir.exists() {
        eprintln!("{}", "Themes directory not found.".red());
        return;
    }

    let current = read_current_theme();
    let entries = match fs::read_dir(&dir) {
        Ok(e) => e,
        Err(err) => {
            eprintln!("{} {}", "Error reading themes:".red(), err);
            return;
        }
    };

    // Collect directory themes first
    let mut dir_themes: Vec<String> = Vec::new();
    let mut themes: Vec<(String, Option<String>)> = Vec::new();

    let mut entries_vec: Vec<_> = entries.filter_map(|e| e.ok()).collect();
    entries_vec.sort_by_key(|e| e.file_name());

    // First pass: find directory themes
    for entry in &entries_vec {
        let path = entry.path();
        if path.is_dir() {
            let prompt_toml = path.join("prompt.toml");
            if prompt_toml.exists() {
                let name = entry.file_name().to_string_lossy().to_string();
                let desc = extract_description(&prompt_toml);
                dir_themes.push(name.clone());
                themes.push((name, desc));
            }
        }
    }

    // Second pass: find flat .toml themes (skip if directory version exists)
    for entry in &entries_vec {
        let path = entry.path();
        if path.is_file() {
            if let Some(ext) = path.extension() {
                if ext == "toml" {
                    let name = path.file_stem()
                        .unwrap_or_default()
                        .to_string_lossy()
                        .to_string();
                    if !dir_themes.contains(&name) {
                        let desc = extract_description(&path);
                        themes.push((name, desc));
                    }
                }
            }
        }
    }

    if themes.is_empty() {
        println!("{}", "No themes found.".yellow());
        return;
    }

    println!("{}", "Available themes:".bold());
    println!();

    for (name, desc) in &themes {
        let is_current = current.as_deref() == Some(name.as_str());
        let marker = if is_current { "* ".green().bold() } else { "  ".normal() };
        let display_name = if is_current {
            name.green().bold()
        } else {
            name.normal()
        };
        match desc {
            Some(d) => println!("{}{}  {}", marker, display_name, d.dimmed()),
            None => println!("{}{}", marker, display_name),
        }
    }
}

fn apply_theme(name: &str) {
    let dir = themes_dir();

    // Try directory theme first
    let dir_path = dir.join(name).join("prompt.toml");
    let flat_path = dir.join(format!("{}.toml", name));

    let source = if dir_path.exists() {
        dir_path
    } else if flat_path.exists() {
        flat_path
    } else {
        eprintln!("{} Theme '{}' not found.", "Error:".red(), name);
        std::process::exit(1);
    };

    let dest = starship_config();

    // Ensure parent directory exists
    if let Some(parent) = dest.parent() {
        if let Err(err) = fs::create_dir_all(parent) {
            eprintln!("{} Could not create config directory: {}", "Error:".red(), err);
            std::process::exit(1);
        }
    }

    if let Err(err) = fs::copy(&source, &dest) {
        eprintln!("{} Could not copy theme: {}", "Error:".red(), err);
        std::process::exit(1);
    }

    if let Err(err) = fs::write(current_theme_file(), name) {
        eprintln!("{} Could not write .current_theme: {}", "Error:".red(), err);
        std::process::exit(1);
    }

    println!("{} Theme '{}' applied.", "OK".green().bold(), name.bold());
}

fn show_current() {
    match read_current_theme() {
        Some(name) => println!("Current theme: {}", name.green().bold()),
        None => println!("{}", "No theme currently set.".yellow()),
    }
}

pub fn run(action: ThemeAction) {
    match action {
        ThemeAction::List => list_themes(),
        ThemeAction::Apply { name } => apply_theme(&name),
        ThemeAction::Current => show_current(),
    }
}
