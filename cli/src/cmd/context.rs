use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

/// Outputs a one-line Kubernetes context summary for Starship.
/// Format: ☸ alias/namespace (or context/namespace if no alias)
/// Outputs nothing if kubectl is unavailable or no context is set.
pub fn run() {
    let context = match get_current_context() {
        Some(c) if !c.is_empty() => c,
        _ => return,
    };

    let namespace = get_current_namespace().unwrap_or_else(|| "default".to_string());
    let aliases = load_aliases();

    // Chercher un alias pour ce contexte
    let display = aliases
        .iter()
        .find(|(_, v)| v.as_str() == context)
        .map(|(k, _)| k.as_str())
        .unwrap_or_else(|| shorten_context(&context));

    print!("☸ {}/{}", display, namespace);
}

fn get_current_context() -> Option<String> {
    let output = Command::new("kubectl")
        .args(["config", "current-context"])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let ctx = String::from_utf8(output.stdout).ok()?.trim().to_string();
    if ctx.is_empty() { None } else { Some(ctx) }
}

fn get_current_namespace() -> Option<String> {
    let output = Command::new("kubectl")
        .args([
            "config", "view", "--minify",
            "-o", "jsonpath={..namespace}",
        ])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let ns = String::from_utf8(output.stdout).ok()?.trim().to_string();
    if ns.is_empty() { None } else { Some(ns) }
}

/// Load kube context aliases from ~/.kube/.context_aliases
fn load_aliases() -> HashMap<String, String> {
    let path = PathBuf::from(
        std::env::var("HOME").unwrap_or_default()
    ).join(".kube/.context_aliases");

    let mut map = HashMap::new();
    if let Ok(content) = fs::read_to_string(&path) {
        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if let Some((alias, context)) = line.split_once('=') {
                map.insert(alias.to_string(), context.to_string());
            }
        }
    }
    map
}

/// Shorten a kube context name by taking the last segment after `/` or `-`.
fn shorten_context(context: &str) -> &str {
    context
        .rsplit_once('/')
        .map(|(_, last)| last)
        .unwrap_or_else(|| {
            context
                .rsplit_once('-')
                .map(|(_, last)| last)
                .unwrap_or(context)
        })
}
