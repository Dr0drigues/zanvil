use std::process::Command;

/// Outputs a one-line Kubernetes context summary for Starship.
/// Format: ☸ context/namespace
/// Outputs nothing if kubectl is unavailable or no context is set.
pub fn run() {
    let context = match get_current_context() {
        Some(c) if !c.is_empty() => c,
        _ => return,
    };

    let namespace = get_current_namespace().unwrap_or_else(|| "default".to_string());
    let short_context = shorten_context(&context);

    print!("☸ {}/{}", short_context, namespace);
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
