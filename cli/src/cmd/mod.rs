pub mod audit;
pub mod bench;
pub mod context;
pub mod doctor;
pub mod modules;
pub mod mr_fanout;
pub mod project;
pub mod secrets;
pub mod sync;
pub mod theme;
pub mod tui_config;
pub mod update;

use colored::*;
use std::fs;

/// Read ZANVIL_VERSION from core/ui.zsh
pub fn read_version() -> String {
    let ui_path = crate::config::zanvil_dir().join("core").join("ui.zsh");
    if let Ok(content) = fs::read_to_string(&ui_path) {
        for line in content.lines() {
            if let Some(rest) = line.strip_prefix("export ZANVIL_VERSION=\"") {
                if let Some(ver) = rest.strip_suffix('"') {
                    return ver.to_string();
                }
            }
        }
    }
    "unknown".to_string()
}

/// Print a boxed header with title and version, matching core/ui.zsh _ui_header style
pub fn print_header(title: &str) {
    let version = read_version();
    // Title left-aligned, version right-aligned inside the box
    // Total inner width = 40 (matches zsh _ui_header)
    let inner_width: usize = 40;
    let padding = inner_width.saturating_sub(title.len() + version.len());
    let border = "─".repeat(inner_width);
    println!("{}", format!("╭{}╮", border).cyan());
    println!(
        "{}  {}{}{}  {}",
        "│".cyan(),
        title,
        " ".repeat(padding),
        version.dimmed(),
        "│".cyan()
    );
    println!("{}", format!("╰{}╯", border).cyan());
}
