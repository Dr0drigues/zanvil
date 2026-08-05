pub mod audit;
pub mod bench;
pub mod conflicts;
pub mod convert;
pub mod context;
pub mod doctor;
pub mod es;
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

/// Print a label-aligned section, matching core/ui.zsh `_ui_section` (14 columns).
pub fn print_section(label: &str, content: &str) {
    println!("{:<14} {}", label.bold(), content);
}

/// Print a boxed header with title and version, matching core/ui.zsh _ui_header style
pub fn print_header(title: &str) {
    let version = read_version();
    // Title left-aligned, version right-aligned inside the box.
    //
    // 42 et non 40, et quatre espaces retires du remplissage plutot que zero : la
    // bordure faisait 40 caracteres pour une ligne de 44, donc le cadre etait ouvert a
    // droite dans les sept commandes qui appellent cette fonction. `_ui_header` prend
    // une largeur de 44 dont 42 d interieur, et compte les deux espaces de chaque cote
    // — c est ce calcul-la qu il fallait reprendre pour que le Rust et le zsh dessinent
    // la meme boite.
    let inner_width: usize = 42;
    let padding = inner_width.saturating_sub(title.len() + version.len() + 4);
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
