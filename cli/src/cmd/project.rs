use clap::Subcommand;
use colored::*;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use toml::Value;

#[derive(Subcommand, Clone)]
pub enum ProjectAction {
    /// List all known projects
    List,
    /// Show resolved configuration for a project
    Config {
        /// Project name (defaults to first known project)
        name: Option<String>,
        /// Environment (defaults to project's default_env)
        #[arg(short, long)]
        env: Option<String>,
        /// Show source of each resolved value
        #[arg(long)]
        show_origin: bool,
    },
    /// Validate manifests: paths, kube contexts, components, hooks
    Doctor {
        /// Project name (defaults to all projects)
        name: Option<String>,
    },
    /// Compare two resolved configurations. Syntax: <name> or <name>:<env>
    Diff {
        a: String,
        b: String,
    },
    /// Print project name whose path contains the given directory (or current dir)
    FindPath {
        dir: Option<String>,
    },
    /// List defined stacks
    Stacks,
    /// Resolve a stack: print one line per member (NAME\tENV\tPATH)
    StackResolve {
        name: String,
        /// Stack env (key of [envs.<e>])
        #[arg(short, long)]
        env: Option<String>,
    },
    /// Emit shell-eval lines to activate a project (used by zproject wrapper)
    Activate {
        name: String,
        #[arg(short, long)]
        env: Option<String>,
    },
    /// Print the resolved shell command for `[commands].<cmd>` of current project
    Run {
        cmd: String,
        /// Project name (defaults to $ZPROJECT_NAME)
        #[arg(long)]
        name: Option<String>,
        /// Environment (defaults to $ZPROJECT_ENV)
        #[arg(short, long)]
        env: Option<String>,
    },
    /// Auto-fill a project manifest from a path
    Scan {
        /// Path to scan
        path: String,
        /// Project name (default: derived from path)
        #[arg(long)]
        name: Option<String>,
        /// Write the manifest without confirmation
        #[arg(long)]
        yes: bool,
    },
    /// List available environments for a project
    Envs {
        /// Project name (defaults to $ZPROJECT_NAME)
        name: Option<String>,
    },
    /// Show active project status (reads shell env vars)
    Status,
}

fn projects_root() -> PathBuf {
    let home = std::env::var("HOME").expect("HOME not set");
    PathBuf::from(home).join(".zsh-env").join("projects")
}

fn load_toml(path: &Path) -> Option<Value> {
    let s = fs::read_to_string(path).ok()?;
    toml::from_str(&s).ok()
}

fn list_projects() -> Vec<String> {
    let root = projects_root();
    let mut names = Vec::new();
    if let Ok(entries) = fs::read_dir(&root) {
        for e in entries.flatten() {
            let path = e.path();
            if !path.is_dir() {
                continue;
            }
            let name = path.file_name().unwrap().to_string_lossy().to_string();
            if name.starts_with('_') || name == "stacks" || name == "local" {
                continue;
            }
            if path.join("project.toml").exists() {
                names.push(name);
            }
        }
    }
    names.sort();
    names
}

fn deep_merge(a: &mut Value, b: Value) {
    match (a, b) {
        (Value::Table(a_tbl), Value::Table(b_tbl)) => {
            for (k, v) in b_tbl {
                // Convention: suffix "+" on a key means "concat arrays" instead of replace.
                // Target key is the name without the "+".
                if let Some(target) = k.strip_suffix('+') {
                    if let Value::Array(new_items) = v {
                        let entry = a_tbl
                            .entry(target.to_string())
                            .or_insert(Value::Array(Vec::new()));
                        if let Value::Array(existing) = entry {
                            existing.extend(new_items);
                        } else {
                            *entry = Value::Array(new_items);
                        }
                        continue;
                    }
                }
                if let Some(a_v) = a_tbl.get_mut(&k) {
                    deep_merge(a_v, v);
                } else {
                    a_tbl.insert(k, v);
                }
            }
        }
        (slot, v) => {
            *slot = v;
        }
    }
}

/// Remplace `${VAR}` dans toutes les chaines de caracteres de `v` par la valeur
/// de la variable d'environnement correspondante. Si la var n'existe pas, laisse tel quel.
fn resolve_env_vars(v: &mut Value) {
    match v {
        Value::String(s) => {
            if s.contains("${") {
                let mut result = String::with_capacity(s.len());
                let bytes = s.as_bytes();
                let mut i = 0;
                while i < bytes.len() {
                    if i + 1 < bytes.len() && bytes[i] == b'$' && bytes[i + 1] == b'{' {
                        if let Some(end) = s[i + 2..].find('}') {
                            let var_name = &s[i + 2..i + 2 + end];
                            match std::env::var(var_name) {
                                Ok(val) => result.push_str(&val),
                                Err(_) => {
                                    result.push_str(&s[i..i + 2 + end + 1]);
                                }
                            }
                            i += 2 + end + 1;
                            continue;
                        }
                    }
                    result.push(bytes[i] as char);
                    i += 1;
                }
                *s = result;
            }
        }
        Value::Array(arr) => {
            for item in arr {
                resolve_env_vars(item);
            }
        }
        Value::Table(t) => {
            for (_, vv) in t.iter_mut() {
                resolve_env_vars(vv);
            }
        }
        _ => {}
    }
}

/// Detecte le composant actif en comparant $PWD avec {project_path}/{components_dir}/*.
/// Retourne le nom du composant (segment de path) ou None.
fn detect_active_component(project_path: &str, components_dir: &str) -> Option<String> {
    let base = if components_dir.is_empty() {
        PathBuf::from(project_path)
    } else {
        PathBuf::from(project_path).join(components_dir)
    };
    let base = std::fs::canonicalize(&base).unwrap_or(base);
    let cwd = std::env::current_dir().ok()?;
    let cwd = std::fs::canonicalize(&cwd).unwrap_or(cwd);
    if !cwd.starts_with(&base) { return None; }
    let rel = cwd.strip_prefix(&base).ok()?;
    rel.components().next()?.as_os_str().to_str().map(|s| s.to_string())
}

/// Rend un chemin absolu: expand ~ et retourne tel quel s'il est deja absolu.
fn expand_path(p: &str) -> String {
    if let Some(rest) = p.strip_prefix("~/") {
        if let Ok(home) = std::env::var("HOME") {
            return format!("{}/{}", home, rest);
        }
    }
    if p == "~" {
        if let Ok(home) = std::env::var("HOME") {
            return home;
        }
    }
    p.to_string()
}

/// Derive le path du projet a partir de la config mergee, si absent :
/// utilise conventions.path_template avec substitution {domain}/{application}/{platform}.
fn derive_path(merged: &mut Value) {
    let tbl = match merged.as_table_mut() {
        Some(t) => t,
        None => return,
    };
    if tbl.contains_key("path") {
        // Deja defini : on expand juste ~
        if let Some(Value::String(s)) = tbl.get_mut("path") {
            *s = expand_path(s);
        }
        return;
    }
    let template = tbl
        .get("conventions")
        .and_then(|c| c.get("path_template"))
        .and_then(|v| v.as_str())
        .map(String::from);
    let template = match template {
        Some(t) => t,
        None => return,
    };
    let domain = tbl.get("domain").and_then(|v| v.as_str()).unwrap_or("");
    let app = tbl.get("application").and_then(|v| v.as_str()).unwrap_or("");
    let platform = tbl.get("platform").and_then(|v| v.as_str()).unwrap_or("");
    let derived = template
        .replace("{domain}", domain)
        .replace("{application}", app)
        .replace("{platform}", platform);
    let derived = expand_path(&derived);
    tbl.insert("path".into(), Value::String(derived));
}

fn get_by_path<'a>(v: &'a Value, path: &str) -> Option<&'a Value> {
    let mut current = v;
    for part in path.split('.') {
        current = current.as_table()?.get(part)?;
    }
    Some(current)
}

fn walk_leaves<F: FnMut(&str, &Value)>(v: &Value, prefix: String, cb: &mut F) {
    match v {
        Value::Table(t) => {
            for (k, vv) in t {
                let key = if prefix.is_empty() {
                    k.clone()
                } else {
                    format!("{}.{}", prefix, k)
                };
                walk_leaves(vv, key, cb);
            }
        }
        _ => cb(&prefix, v),
    }
}

struct Layer {
    source: String,
    value: Value,
}

fn build_layers(project_name: &str, env: Option<&str>) -> Result<(Vec<Layer>, Option<String>), String> {
    let root = projects_root();
    let project_dir = root.join(project_name);
    let project_toml_path = project_dir.join("project.toml");
    if !project_toml_path.exists() {
        return Err(format!("Project '{}' not found at {}", project_name, project_toml_path.display()));
    }

    let project_value = load_toml(&project_toml_path)
        .ok_or_else(|| format!("Failed to parse {}", project_toml_path.display()))?;

    let env_name = env.map(String::from).or_else(|| {
        project_value
            .get("default_env")
            .and_then(|v| v.as_str().map(String::from))
    });

    let inherits: Vec<String> = project_value
        .get("inherits")
        .and_then(|v| v.as_array())
        .map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect())
        .unwrap_or_default();

    let mut layers = Vec::new();

    let defaults_path = root.join("_defaults.toml");
    if let Some(v) = load_toml(&defaults_path) {
        layers.push(Layer { source: "_defaults.toml".into(), value: v });
    }

    for g in &inherits {
        let p = root.join("_groups").join(format!("{}.toml", g));
        if let Some(v) = load_toml(&p) {
            layers.push(Layer { source: format!("_groups/{}.toml", g), value: v });
        }
    }

    layers.push(Layer { source: format!("{}/project.toml", project_name), value: project_value });

    if let Some(e) = &env_name {
        let p = project_dir.join("envs").join(format!("{}.toml", e));
        if p.exists() {
            if let Some(v) = load_toml(&p) {
                layers.push(Layer { source: format!("{}/envs/{}.toml", project_name, e), value: v });
            } else {
                return Err(format!("Failed to parse {}", p.display()));
            }
        } else if env.is_some() {
            // Env explicitement demande mais fichier absent: erreur.
            // Pour un default_env absent on laisse passer silencieusement.
            let available = list_env_files(project_name);
            let hint = if available.is_empty() {
                String::new()
            } else {
                format!(" (available: {})", available.join(", "))
            };
            return Err(format!("Env '{}' not found for project '{}'{}", e, project_name, hint));
        }
    }

    let local_path = root.join("local").join(format!("{}.toml", project_name));
    if let Some(v) = load_toml(&local_path) {
        layers.push(Layer { source: format!("local/{}.toml", project_name), value: v });
    }

    Ok((layers, env_name))
}

fn resolve(layers: &[Layer]) -> (Value, BTreeMap<String, String>) {
    let mut merged = Value::Table(toml::map::Map::new());
    for layer in layers {
        deep_merge(&mut merged, layer.value.clone());
    }

    let mut origins = BTreeMap::new();
    walk_leaves(&merged, String::new(), &mut |k, _v| {
        for layer in layers.iter().rev() {
            if get_by_path(&layer.value, k).is_some() {
                origins.insert(k.to_string(), layer.source.clone());
                break;
            }
        }
    });

    (merged, origins)
}

pub fn run(action: ProjectAction) {
    match action {
        ProjectAction::List => run_list(),
        ProjectAction::Config { name, env, show_origin } => run_config(name, env, show_origin),
        ProjectAction::Doctor { name } => run_doctor(name),
        ProjectAction::Diff { a, b } => run_diff(a, b),
        ProjectAction::Scan { path, name, yes } => run_scan(path, name, yes),
        ProjectAction::Activate { name, env } => run_activate(name, env),
        ProjectAction::FindPath { dir } => run_find_path(dir),
        ProjectAction::Run { cmd, name, env } => run_run(cmd, name, env),
        ProjectAction::Stacks => run_stacks(),
        ProjectAction::StackResolve { name, env } => run_stack_resolve(name, env),
        ProjectAction::Envs { name } => run_envs(name),
        ProjectAction::Status => run_status(),
    }
}

fn list_stacks() -> Vec<String> {
    let dir = projects_root().join("stacks");
    let mut names = Vec::new();
    if let Ok(entries) = fs::read_dir(&dir) {
        for e in entries.flatten() {
            let p = e.path();
            if p.extension().and_then(|x| x.to_str()) == Some("toml") {
                if let Some(stem) = p.file_stem().and_then(|s| s.to_str()) {
                    names.push(stem.to_string());
                }
            }
        }
    }
    names.sort();
    names
}

fn run_stacks() {
    super::print_header("zproject stacks");
    let stacks = list_stacks();
    if stacks.is_empty() {
        println!("{}", "No stacks defined.".yellow());
        return;
    }
    for s in stacks {
        let p = projects_root().join("stacks").join(format!("{}.toml", s));
        if let Some(v) = load_toml(&p) {
            let members: Vec<String> = v
                .get("members")
                .and_then(|m| m.as_array())
                .map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect())
                .unwrap_or_default();
            let envs: Vec<String> = v
                .get("envs")
                .and_then(|e| e.as_table())
                .map(|t| t.keys().cloned().collect())
                .unwrap_or_default();
            println!(
                "  {}  {}  {}",
                s.cyan().bold(),
                format!("members={}", members.join(",")).dimmed(),
                format!("envs={}", envs.join(",")).dimmed()
            );
        }
    }
}

fn run_stack_resolve(name: String, env: Option<String>) {
    let path = projects_root().join("stacks").join(format!("{}.toml", name));
    let v = match load_toml(&path) {
        Some(v) => v,
        None => {
            eprintln!("stack '{}' not found at {}", name, path.display());
            std::process::exit(1);
        }
    };
    let members: Vec<String> = v
        .get("members")
        .and_then(|m| m.as_array())
        .map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect())
        .unwrap_or_default();
    if members.is_empty() {
        eprintln!("stack '{}' has no members", name);
        std::process::exit(1);
    }
    // Table envs.<env> = { member = env_name, ... }
    let env_map: toml::map::Map<String, Value> = if let Some(e) = &env {
        match v.get("envs").and_then(|t| t.get(e)).and_then(|x| x.as_table()) {
            Some(t) => t.clone(),
            None => {
                let available: Vec<String> = v
                    .get("envs")
                    .and_then(|t| t.as_table())
                    .map(|t| t.keys().cloned().collect())
                    .unwrap_or_default();
                eprintln!(
                    "stack env '{}' not defined (available: {})",
                    e,
                    available.join(", ")
                );
                std::process::exit(1);
            }
        }
    } else {
        toml::map::Map::new()
    };

    // Imprime une ligne par membre : NAME<TAB>ENV<TAB>PATH
    for m in &members {
        let member_env = env_map.get(m).and_then(|v| v.as_str());
        let (merged, env_eff) = match resolve_merged(m, member_env) {
            Ok(x) => x,
            Err(err) => {
                eprintln!("{}: {}", m, err);
                std::process::exit(1);
            }
        };
        let path = merged.get("path").and_then(|v| v.as_str()).unwrap_or("");
        println!("{}\t{}\t{}", m, env_eff.as_deref().unwrap_or(""), path);
    }
}

fn run_run(cmd: String, name_arg: Option<String>, env_arg: Option<String>) {
    let name = name_arg
        .or_else(|| std::env::var("ZPROJECT_NAME").ok())
        .unwrap_or_default();
    if name.is_empty() {
        eprintln!("no active project (ZPROJECT_NAME unset) — pass --name or activate first");
        std::process::exit(1);
    }
    let env = env_arg.or_else(|| std::env::var("ZPROJECT_ENV").ok());
    let (merged, _) = match resolve_merged(&name, env.as_deref()) {
        Ok(x) => x,
        Err(e) => { eprintln!("{}", e); std::process::exit(1); }
    };
    let raw = merged
        .get("commands")
        .and_then(|c| c.get(&cmd))
        .and_then(|v| v.as_str());
    let raw = match raw {
        Some(r) => r,
        None => {
            let available: Vec<&str> = merged
                .get("commands")
                .and_then(|c| c.as_table())
                .map(|t| t.keys().map(|s| s.as_str()).collect())
                .unwrap_or_default();
            let hint = if available.is_empty() {
                String::new()
            } else {
                format!(" (available: {})", available.join(", "))
            };
            eprintln!("command '{}' not defined for project '{}'{}", cmd, name, hint);
            std::process::exit(1);
        }
    };
    let rendered = render_template(raw, &merged);
    let path = merged.get("path").and_then(|v| v.as_str()).unwrap_or("");
    if path.is_empty() {
        println!("{}", rendered);
    } else {
        println!("(cd {} && {})", shell_escape(path), rendered);
    }
}

fn run_find_path(dir: Option<String>) {
    let target = match dir {
        Some(d) => expand_path(&d),
        None => match std::env::current_dir() {
            Ok(p) => p.to_string_lossy().to_string(),
            Err(_) => return,
        },
    };
    let target_pb = match std::fs::canonicalize(&target) {
        Ok(p) => p,
        Err(_) => PathBuf::from(&target),
    };
    // Cherche le projet dont le path est prefixe de target
    let mut best: Option<(String, usize)> = None;
    for name in list_projects() {
        let merged = match resolve_merged(&name, None) {
            Ok((m, _)) => m,
            Err(_) => continue,
        };
        let path = match merged.get("path").and_then(|v| v.as_str()) {
            Some(p) => p.to_string(),
            None => continue,
        };
        let project_pb = match std::fs::canonicalize(&path) {
            Ok(p) => p,
            Err(_) => PathBuf::from(&path),
        };
        if target_pb.starts_with(&project_pb) {
            let depth = project_pb.components().count();
            if best.as_ref().map_or(true, |(_, d)| depth > *d) {
                best = Some((name, depth));
            }
        }
    }
    if let Some((name, _)) = best {
        println!("{}", name);
    }
}

fn shell_escape(s: &str) -> String {
    // Quoting POSIX single-quote: close, echo a literal single-quote, reopen.
    let mut out = String::with_capacity(s.len() + 2);
    out.push('\'');
    for c in s.chars() {
        if c == '\'' {
            out.push_str("'\\''");
        } else {
            out.push(c);
        }
    }
    out.push('\'');
    out
}

/// Remplace `{{section.key}}` dans `s` par la valeur trouvee dans `merged`.
/// Si la clef est absente ou non-string, laisse le placeholder tel quel.
fn render_template(s: &str, merged: &Value) -> String {
    let mut out = String::with_capacity(s.len());
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if i + 1 < bytes.len() && bytes[i] == b'{' && bytes[i + 1] == b'{' {
            if let Some(end) = s[i + 2..].find("}}") {
                let key = s[i + 2..i + 2 + end].trim();
                match get_by_path(merged, key).and_then(|v| v.as_str()) {
                    Some(val) => out.push_str(val),
                    None => out.push_str(&s[i..i + 2 + end + 2]),
                }
                i += 2 + end + 2;
                continue;
            }
        }
        out.push(bytes[i] as char);
        i += 1;
    }
    out
}

fn emit_hook(kind_script: bool, raw: &str, project_path: &str, merged: &Value, is_on_leave: bool) {
    let prefix = if is_on_leave { "__zproject_queue_on_leave" } else {
        if kind_script { "__zproject_run_hook_script" } else { "__zproject_run_hook_cmd" }
    };
    if kind_script {
        let script = raw.strip_prefix('@').unwrap_or(raw);
        let resolved = if script.starts_with('/') || script.starts_with('~') {
            expand_path(script)
        } else if !project_path.is_empty() {
            format!("{}/{}", project_path, script)
        } else {
            script.to_string()
        };
        let payload = if is_on_leave { format!("SCRIPT:{}", resolved) } else { resolved };
        println!("{} {}", prefix, shell_escape(&payload));
    } else {
        let rendered = render_template(raw, merged);
        let payload = if is_on_leave { format!("CMD:{}", rendered) } else { rendered };
        println!("{} {}", prefix, shell_escape(&payload));
    }
}

fn run_activate(name: String, env: Option<String>) {
    let (merged, env_name) = match resolve_merged(&name, env.as_deref()) {
        Ok(x) => x,
        Err(e) => {
            eprintln!("{}", e);
            std::process::exit(1);
        }
    };

    // Metadonnees d'etat (exportees vers le wrapper zsh)
    println!("# zproject activate: {} [{}]", name, env_name.as_deref().unwrap_or("-"));
    println!("export ZPROJECT_NAME={}", shell_escape(&name));
    if let Some(e) = &env_name {
        println!("export ZPROJECT_ENV={}", shell_escape(e));
    }
    let path = merged.get("path").and_then(|v| v.as_str()).unwrap_or("");
    if !path.is_empty() {
        println!("export ZPROJECT_PATH={}", shell_escape(path));
        println!("__zproject_cd {}", shell_escape(path));
    }

    // Detection du composant actif (si cwd est dans components/<name>)
    let components_dir = merged
        .get("conventions")
        .and_then(|c| c.get("components_dir"))
        .and_then(|v| v.as_str())
        .unwrap_or("components")
        .to_string();
    let active_component: Option<String> = if !path.is_empty() {
        detect_active_component(path, &components_dir)
    } else {
        None
    };
    // Cloner runtimes/commands du composant avant tout emprunt de merged
    let comp_runtimes: Option<toml::map::Map<String, Value>> = active_component
        .as_ref()
        .and_then(|cn| {
            merged.get("components")?.get(cn.as_str())?.get("runtimes")?.as_table().cloned()
        });
    let comp_commands: Option<toml::map::Map<String, Value>> = active_component
        .as_ref()
        .and_then(|cn| {
            merged.get("components")?.get(cn.as_str())?.get("commands")?.as_table().cloned()
        });
    if let Some(comp) = &active_component {
        println!("export ZPROJECT_COMPONENT={}", shell_escape(comp));
        println!("__zproject_track_env 'ZPROJECT_COMPONENT'");
    }

    // Kube
    let mut kube_ctx: Option<String> = None;
    let mut kube_ns: Option<String> = None;
    if let Some(Value::Table(kube)) = merged.get("kube") {
        if let Some(ctx) = kube.get("context").and_then(|v| v.as_str()) {
            if !ctx.is_empty() {
                println!("__zproject_kube_context {}", shell_escape(ctx));
                kube_ctx = Some(ctx.to_string());
            }
        }
        if let Some(ns) = kube.get("namespace").and_then(|v| v.as_str()) {
            if !ns.is_empty() {
                println!("__zproject_kube_namespace {}", shell_escape(ns));
                kube_ns = Some(ns.to_string());
            }
        }
    }
    // Expose le couple ctx/ns via des vars + aliases k9s/kubectl pour force les flags
    // (k9s notamment garde un lastNs propre qui peut override le kubeconfig).
    if let Some(ctx) = &kube_ctx {
        println!("export ZPROJECT_KUBE_CONTEXT={}", shell_escape(ctx));
        println!("__zproject_track_env 'ZPROJECT_KUBE_CONTEXT'");
    }
    if let Some(ns) = &kube_ns {
        println!("export ZPROJECT_KUBE_NAMESPACE={}", shell_escape(ns));
        println!("__zproject_track_env 'ZPROJECT_KUBE_NAMESPACE'");
    }
    // Note: la fonction `k()` de modules/kube/kube_config.zsh est zproject-aware
    // et lit ZPROJECT_KUBE_CONTEXT / ZPROJECT_KUBE_NAMESPACE quand appelee sans args.
    let _ = (&kube_ctx, &kube_ns);

    // Env vars (avec templating {{...}})
    if let Some(env_tbl) = merged.get("env").and_then(|v| v.as_table()) {
        for (k, v) in env_tbl {
            if let Some(s) = v.as_str() {
                let rendered = render_template(s, &merged);
                println!("export {}={}", k, shell_escape(&rendered));
                println!("__zproject_track_env {}", shell_escape(k));
            }
        }
    }

    // Commands -> alias shell temporaires (composant prioritaire sur projet).
    // Chaque alias execute la commande dans le path du composant ou du projet.
    let cmd_path = active_component.as_ref().map(|cn| {
        let base = if components_dir.is_empty() {
            path.to_string()
        } else {
            format!("{}/{}/{}", path, components_dir, cn)
        };
        base
    }).unwrap_or_else(|| path.to_string());

    let cmds_ref: Option<&toml::map::Map<String, Value>> = comp_commands
        .as_ref()
        .or_else(|| merged.get("commands").and_then(|v| v.as_table()));
    if let Some(cmds) = cmds_ref {
        for (k, v) in cmds {
            if let Some(raw) = v.as_str() {
                let rendered = render_template(raw, &merged);
                let alias_value = if cmd_path.is_empty() {
                    rendered
                } else {
                    format!("(cd {} && {})", shell_escape(&cmd_path), rendered)
                };
                println!("alias {}={}", k, shell_escape(&alias_value));
                println!("__zproject_track_alias {}", shell_escape(k));
            }
        }
    }

    // Hooks on_leave : queue vers le state (rejoues au zproject exit)
    if let Some(hooks) = merged.get("hooks").and_then(|h| h.get("on_leave")).and_then(|v| v.as_array()) {
        for item in hooks {
            if let Some(cmd) = item.as_str() {
                let is_script = cmd.starts_with('@');
                emit_hook(is_script, cmd, path, &merged, true);
            }
        }
    }

    // Runtimes -> mise use <tool>@<version> (composant prioritaire sur projet).
    let rt_ref: Option<&toml::map::Map<String, Value>> = comp_runtimes
        .as_ref()
        .or_else(|| merged.get("runtimes").and_then(|v| v.as_table()));
    if let Some(rt) = rt_ref {
        for (tool, ver) in rt {
            if let Some(v) = ver.as_str() {
                if !v.is_empty() {
                    println!("__zproject_runtime_use {} {}", shell_escape(tool), shell_escape(v));
                    println!("__zproject_state_append {}", shell_escape(&format!("RUNTIME={}", tool)));
                }
            }
        }
    }

    // Hooks on_enter : executes sequentiellement, echec -> rollback (zproject exit)
    if let Some(hooks) = merged.get("hooks").and_then(|h| h.get("on_enter")).and_then(|v| v.as_array()) {
        for item in hooks {
            if let Some(cmd) = item.as_str() {
                let is_script = cmd.starts_with('@');
                emit_hook(is_script, cmd, path, &merged, false);
            }
        }
    }
}

fn run_envs(name: Option<String>) {
    let name = name
        .or_else(|| std::env::var("ZPROJECT_NAME").ok().filter(|s| !s.is_empty()))
        .unwrap_or_else(|| {
            eprintln!("{}", "no project specified (pass name or activate one first)".red());
            std::process::exit(1);
        });
    let envs = list_env_files(&name);
    if envs.is_empty() {
        eprintln!("{}", format!("no envs for '{}'", name).yellow());
    } else {
        let default = {
            let root = projects_root().join(&name).join("project.toml");
            load_toml(&root)
                .and_then(|v| v.get("default_env").and_then(|d| d.as_str().map(String::from)))
        };
        for e in &envs {
            if default.as_deref() == Some(e.as_str()) {
                println!("{} {}", e, "(default)".dimmed());
            } else {
                println!("{}", e);
            }
        }
    }
}

fn run_status() {
    let name = std::env::var("ZPROJECT_NAME").ok().filter(|s| !s.is_empty());
    let env  = std::env::var("ZPROJECT_ENV").ok().filter(|s| !s.is_empty());
    let path = std::env::var("ZPROJECT_PATH").ok().filter(|s| !s.is_empty());
    let kube_ctx = std::env::var("ZPROJECT_KUBE_CONTEXT").ok().filter(|s| !s.is_empty());
    let kube_ns  = std::env::var("ZPROJECT_KUBE_NAMESPACE").ok().filter(|s| !s.is_empty());

    if name.is_none() {
        println!("inactive");
        return;
    }
    let name = name.unwrap();
    println!("{} {}", "project:".dimmed(), name.cyan().bold());
    if let Some(e) = &env  { println!("{} {}", "env:    ".dimmed(), e.cyan()); }
    if let Some(p) = &path { println!("{} {}", "path:   ".dimmed(), p.dimmed()); }
    if let Some(c) = &kube_ctx { println!("{} {}", "kube:   ".dimmed(), c.cyan()); }
    if let Some(n) = &kube_ns  { println!("{} {}", "ns:     ".dimmed(), n.dimmed()); }
}

fn parse_spec(spec: &str) -> (String, Option<String>) {
    match spec.split_once(':') {
        Some((n, e)) => (n.to_string(), Some(e.to_string())),
        None => (spec.to_string(), None),
    }
}

fn value_to_display(v: &Value) -> String {
    match v {
        Value::String(s) => format!("\"{}\"", s),
        other => other.to_string(),
    }
}

fn run_diff(a_spec: String, b_spec: String) {
    super::print_header("zproject diff");
    let (a_name, a_env) = parse_spec(&a_spec);
    let (b_name, b_env) = parse_spec(&b_spec);

    let (a_merged, a_env_eff) = match resolve_merged(&a_name, a_env.as_deref()) {
        Ok(x) => x,
        Err(e) => { eprintln!("{}", e.red()); std::process::exit(1); }
    };
    let (b_merged, b_env_eff) = match resolve_merged(&b_name, b_env.as_deref()) {
        Ok(x) => x,
        Err(e) => { eprintln!("{}", e.red()); std::process::exit(1); }
    };

    let a_label = format!("{}:{}", a_name, a_env_eff.as_deref().unwrap_or("-"));
    let b_label = format!("{}:{}", b_name, b_env_eff.as_deref().unwrap_or("-"));
    println!("{} {}", "A:".dimmed(), a_label.cyan());
    println!("{} {}", "B:".dimmed(), b_label.cyan());
    println!("{}", "─".repeat(60).dimmed());

    let mut a_leaves: BTreeMap<String, String> = BTreeMap::new();
    walk_leaves(&a_merged, String::new(), &mut |k, v| {
        a_leaves.insert(k.to_string(), value_to_display(v));
    });
    let mut b_leaves: BTreeMap<String, String> = BTreeMap::new();
    walk_leaves(&b_merged, String::new(), &mut |k, v| {
        b_leaves.insert(k.to_string(), value_to_display(v));
    });

    let mut keys: Vec<&String> = a_leaves.keys().chain(b_leaves.keys()).collect();
    keys.sort();
    keys.dedup();

    let mut diffs = 0u32;
    let mut only_a = 0u32;
    let mut only_b = 0u32;
    for k in keys {
        match (a_leaves.get(k), b_leaves.get(k)) {
            (Some(av), Some(bv)) if av == bv => {}
            (Some(av), Some(bv)) => {
                println!("  {} {}", "~".yellow(), k.bold());
                println!("      A {}", av.red());
                println!("      B {}", bv.green());
                diffs += 1;
            }
            (Some(av), None) => {
                println!("  {} {} = {}", "-".red(), k, av.red());
                only_a += 1;
            }
            (None, Some(bv)) => {
                println!("  {} {} = {}", "+".green(), k, bv.green());
                only_b += 1;
            }
            _ => {}
        }
    }

    println!("{}", "─".repeat(60).dimmed());
    if diffs + only_a + only_b == 0 {
        println!("{} identical", "✔".green());
    } else {
        println!(
            "{} diff(s), {} only-A, {} only-B",
            diffs, only_a, only_b
        );
    }
}

// ───────────────────── scan ─────────────────────

#[derive(Debug)]
struct ScannedProject {
    name: String,
    application: String,
    platform: Option<String>,
    domain: Option<String>,
    path: String,
    inherits: Vec<String>,
    components: Vec<(String, String, Option<String>)>, // (name, type, dir_override)
    repo_url: Option<String>,
    default_branch: Option<String>,
    runtimes: Vec<(String, String)>, // (tool, version)
}

/// Détecte les runtimes depuis les fichiers de config courants dans un répertoire.
/// Priorité : mise.toml > .tool-versions > .nvmrc/.node-version > .sdkmanrc
fn detect_runtimes(path: &Path) -> Vec<(String, String)> {
    let mut runtimes: std::collections::BTreeMap<String, String> = Default::default();

    // .sdkmanrc  →  java=21.0.5-zulu  maven=3.9.6
    let sdkmanrc = path.join(".sdkmanrc");
    if let Ok(content) = fs::read_to_string(&sdkmanrc) {
        for line in content.lines() {
            let line = line.trim();
            if line.starts_with('#') || line.is_empty() { continue; }
            if let Some((k, v)) = line.split_once('=') {
                let tool = k.trim();
                let raw_ver = v.trim();
                // Normalise : "21.0.5-zulu" → "21" pour java; "3.9.6" → "3.9.6" pour maven
                let ver = match tool {
                    "java" => raw_ver.split('.').next().unwrap_or(raw_ver).to_string(),
                    _ => raw_ver.to_string(),
                };
                runtimes.entry(tool.to_string()).or_insert(ver);
            }
        }
    }

    // .tool-versions  →  node 20.11.0\njava 21
    let tool_versions = path.join(".tool-versions");
    if let Ok(content) = fs::read_to_string(&tool_versions) {
        for line in content.lines() {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 {
                runtimes.entry(parts[0].to_string()).or_insert_with(|| parts[1].to_string());
            }
        }
    }

    // mise.toml  →  [tools]\nnode = "lts"\nrust = "stable"
    for filename in &["mise.toml", ".mise.toml"] {
        let mise_path = path.join(filename);
        if let Ok(content) = fs::read_to_string(&mise_path) {
            if let Ok(v) = toml::from_str::<Value>(&content) {
                if let Some(Value::Table(tools)) = v.get("tools") {
                    for (tool, ver) in tools {
                        let ver_str = match ver {
                            Value::String(s) => s.clone(),
                            Value::Array(a) => a.first()
                                .and_then(|x| x.as_str())
                                .unwrap_or("latest")
                                .to_string(),
                            other => other.to_string(),
                        };
                        runtimes.entry(tool.clone()).or_insert(ver_str);
                    }
                }
            }
        }
    }

    // .nvmrc / .node-version  →  v20.11.0 ou 20 ou lts
    for filename in &[".nvmrc", ".node-version"] {
        let p = path.join(filename);
        if let Ok(content) = fs::read_to_string(&p) {
            let ver = content.trim().trim_start_matches('v').to_string();
            if !ver.is_empty() {
                runtimes.entry("node".to_string()).or_insert(ver);
            }
        }
    }

    runtimes.into_iter().collect()
}

/// Déduit un git remote URL propre (sans token oauth2: embarqué)
fn clean_remote_url(raw: &str) -> String {
    // Supprime le prefixe oauth2:<token>@ des URLs HTTPS GitLab
    if let Some(at_pos) = raw.find('@') {
        if raw.starts_with("https://") || raw.starts_with("http://") {
            let host_and_rest = &raw[at_pos + 1..];
            return format!("https://{}", host_and_rest);
        }
    }
    raw.to_string()
}

fn git_remote_url(path: &Path) -> Option<String> {
    let out = std::process::Command::new("git")
        .args(["-C", &path.to_string_lossy(), "remote", "get-url", "origin"])
        .output()
        .ok()?;
    if !out.status.success() { return None; }
    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if s.is_empty() { None } else { Some(s) }
}

fn git_default_branch(path: &Path) -> Option<String> {
    let out = std::process::Command::new("git")
        .args(["-C", &path.to_string_lossy(), "symbolic-ref", "--short", "HEAD"])
        .output()
        .ok()?;
    if !out.status.success() { return None; }
    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if s.is_empty() { None } else { Some(s) }
}

fn component_type_from_name(name: &str) -> &'static str {
    let lower = name.to_lowercase();
    if lower.starts_with("api-") || lower.starts_with("api_") || lower == "api" { "api" }
    else if lower.starts_with("bff") { "bff" }
    else if lower.starts_with("runner-") || lower.starts_with("job-") || lower.starts_with("batch-") { "runner" }
    else if lower.starts_with("library-") || lower.starts_with("lib-") { "library" }
    else if lower.starts_with("docs") || lower == "documentation" { "docs" }
    else if lower.starts_with("infra") { "infra" }
    else if lower.starts_with("config") { "config" }
    else { "app" }
}

fn detect_from_path(path: &Path) -> (Option<String>, Option<String>, Option<String>) {
    // Retourne (domain, platform, application) si le path matche une convention connue
    let home = std::env::var("HOME").unwrap_or_default();
    let s = path.to_string_lossy().to_string();
    let work = format!("{}/work", home);

    // PTF: ~/work/apis/<domain>/applications/<app>
    if let Some(rest) = s.strip_prefix(&format!("{}/apis/", work)) {
        let parts: Vec<&str> = rest.split('/').collect();
        if parts.len() >= 3 && parts[1] == "applications" {
            return (Some(parts[0].to_string()), Some("ptf".to_string()), Some(parts[2].to_string()));
        }
    }
    // CaaS: ~/work/<domain>/applications/<app>
    if let Some(rest) = s.strip_prefix(&format!("{}/", work)) {
        let parts: Vec<&str> = rest.split('/').collect();
        if parts.len() >= 3 && parts[1] == "applications" {
            return (Some(parts[0].to_string()), Some("caas".to_string()), Some(parts[2].to_string()));
        }
    }
    (None, None, None)
}

fn scan_components(project_path: &Path, components_dir: &str) -> Vec<(String, String, Option<String>)> {
    let search_dir = if components_dir.is_empty() {
        project_path.to_path_buf()
    } else {
        project_path.join(components_dir)
    };
    let flat_ptf = components_dir.is_empty();
    let mut out = Vec::new();
    if let Ok(entries) = fs::read_dir(&search_dir) {
        for e in entries.flatten() {
            let p = e.path();
            if !p.is_dir() { continue; }
            let name = p.file_name().unwrap().to_string_lossy().to_string();
            if name.starts_with('.') { continue; }
            // Toujours ignorer les sous-dossiers standards de conteneur
            if name == "configurations" || name == "configuration" || name == "libraries"
                || name == "infrastructure" || name == "components"
            {
                continue;
            }
            // En PTF (flat), on ne prend que les dossiers qui matchent un prefixe typique
            // pour eviter de ramasser data/, docs/, scripts/, etc.
            if flat_ptf {
                let lower = name.to_lowercase();
                let is_component = lower.starts_with("api-")
                    || lower.starts_with("bff-") || lower == "bff"
                    || lower.starts_with("runner-")
                    || lower.starts_with("library-") || lower.starts_with("lib-")
                    || lower.starts_with("job-") || lower.starts_with("batch-");
                if !is_component { continue; }
            }
            let ctype = component_type_from_name(&name).to_string();
            // Nom logique = nom du dossier (pas de renommage : evite les collisions).
            // L'utilisateur peut renommer manuellement et ajouter `dir = "..."`.
            out.push((name.clone(), ctype, None));
        }
    }
    out.sort_by(|a, b| a.0.cmp(&b.0));
    out
}

fn scan_path(path_str: &str, name_override: Option<&str>) -> Result<ScannedProject, String> {
    let expanded = expand_path(path_str);
    let path = PathBuf::from(&expanded);
    if !path.is_dir() {
        return Err(format!("Path not found or not a directory: {}", expanded));
    }
    let (domain, platform, app_detected) = detect_from_path(&path);
    let application = app_detected
        .clone()
        .unwrap_or_else(|| path.file_name().unwrap().to_string_lossy().to_string());
    let name = name_override
        .map(String::from)
        .unwrap_or_else(|| match platform.as_deref() {
            Some(p) => format!("{}-{}", application, p),
            None => application.clone(),
        });

    let mut inherits = Vec::new();
    if let Some(p) = &platform { inherits.push(p.clone()); }
    if let Some(d) = &domain { inherits.push(d.clone()); }

    let components_dir = match platform.as_deref() {
        Some("caas") => "components",
        _ => "",
    };
    let components = scan_components(&path, components_dir);

    let repo_url = git_remote_url(&path).map(|u| clean_remote_url(&u));
    let default_branch = git_default_branch(&path);

    // Runtimes : scan récursif dans les composants pour union des outils détectés
    let mut runtimes = detect_runtimes(&path);
    let search_dir = if components_dir.is_empty() { path.clone() } else { path.join(components_dir) };
    if let Ok(entries) = fs::read_dir(&search_dir) {
        for e in entries.flatten() {
            let p = e.path();
            if p.is_dir() {
                for (tool, ver) in detect_runtimes(&p) {
                    if !runtimes.iter().any(|(t, _)| t == &tool) {
                        runtimes.push((tool, ver));
                    }
                }
            }
        }
    }
    runtimes.sort_by(|a, b| a.0.cmp(&b.0));

    Ok(ScannedProject {
        name,
        application,
        platform,
        domain,
        path: expanded,
        inherits,
        components,
        repo_url,
        default_branch,
        runtimes,
    })
}

fn render_scanned_toml(sp: &ScannedProject, use_template: bool) -> String {
    let mut out = String::new();
    out.push_str(&format!("name = \"{}\"\n", sp.name));
    out.push_str(&format!("application = \"{}\"\n", sp.application));
    if let Some(p) = &sp.platform { out.push_str(&format!("platform = \"{}\"\n", p)); }
    if let Some(d) = &sp.domain { out.push_str(&format!("domain = \"{}\"\n", d)); }
    if !sp.inherits.is_empty() {
        let inner: Vec<String> = sp.inherits.iter().map(|s| format!("\"{}\"", s)).collect();
        out.push_str(&format!("inherits = [{}]\n", inner.join(", ")));
    }
    if !use_template {
        out.push_str(&format!("path = \"{}\"\n", sp.path));
    }
    // default_env heuristique
    let default_env = match sp.platform.as_deref() {
        Some("caas") => Some("caas-dev"),
        Some("ptf") => Some("ptf-dev"),
        _ => None,
    };
    if let Some(e) = default_env {
        out.push_str(&format!("default_env = \"{}\"\n", e));
    }

    if sp.repo_url.is_some() || sp.default_branch.is_some() {
        out.push_str("\n[repo]\n");
        if let Some(u) = &sp.repo_url { out.push_str(&format!("url = \"{}\"\n", u)); }
        if let Some(b) = &sp.default_branch { out.push_str(&format!("default_branch = \"{}\"\n", b)); }
    }

    if !sp.runtimes.is_empty() {
        out.push_str("\n[runtimes]\n");
        for (tool, ver) in &sp.runtimes {
            out.push_str(&format!("{} = \"{}\"\n", tool, ver));
        }
    }

    for (cname, ctype, dir_override) in &sp.components {
        out.push_str(&format!("\n[components.{}]\n", cname));
        out.push_str(&format!("type = \"{}\"\n", ctype));
        if let Some(d) = dir_override {
            out.push_str(&format!("dir = \"{}\"\n", d));
        }
    }
    out
}

fn run_scan(path: String, name: Option<String>, yes: bool) {
    super::print_header("zproject scan");
    let sp = match scan_path(&path, name.as_deref()) {
        Ok(s) => s,
        Err(e) => { eprintln!("{}", e.red()); std::process::exit(1); }
    };

    let project_dir = projects_root().join(&sp.name);
    let project_toml = project_dir.join("project.toml");
    let exists = project_toml.exists();

    // Si on est dans une convention connue, on n'ecrit pas le path (derive via template)
    let use_template = sp.platform.is_some() && sp.domain.is_some();
    let rendered = render_scanned_toml(&sp, use_template);

    println!("{} {}", "target:".dimmed(), project_toml.display().to_string().cyan());
    println!("{}", "─".repeat(60).dimmed());

    if exists {
        // Diff structurel entre l'existant et le nouveau contenu scanne
        let existing: Option<Value> = load_toml(&project_toml);
        let scanned: Option<Value> = toml::from_str(&rendered).ok();
        match (existing, scanned) {
            (Some(a), Some(b)) => {
                let mut a_leaves: BTreeMap<String, String> = BTreeMap::new();
                walk_leaves(&a, String::new(), &mut |k, v| {
                    a_leaves.insert(k.to_string(), value_to_display(v));
                });
                let mut b_leaves: BTreeMap<String, String> = BTreeMap::new();
                walk_leaves(&b, String::new(), &mut |k, v| {
                    b_leaves.insert(k.to_string(), value_to_display(v));
                });
                let mut keys: Vec<&String> = a_leaves.keys().chain(b_leaves.keys()).collect();
                keys.sort();
                keys.dedup();

                println!("{}", "diff: existing (A) → scanned (B)".bold());
                let mut changes = 0u32;
                for k in keys {
                    match (a_leaves.get(k), b_leaves.get(k)) {
                        (Some(av), Some(bv)) if av == bv => {}
                        (Some(av), Some(bv)) => {
                            println!("  {} {}", "~".yellow(), k.bold());
                            println!("      A {}", av.red());
                            println!("      B {}", bv.green());
                            changes += 1;
                        }
                        (Some(av), None) => {
                            println!("  {} {} = {}  {}", "-".red(), k, av.red(), "(kept only in existing — will be dropped)".dimmed());
                            changes += 1;
                        }
                        (None, Some(bv)) => {
                            println!("  {} {} = {}", "+".green(), k, bv.green());
                            changes += 1;
                        }
                        _ => {}
                    }
                }
                if changes == 0 {
                    println!("  {} no changes", "·".dimmed());
                }
            }
            _ => {
                println!("{}", "⚠ impossible to diff (existing file unparseable)".yellow());
                println!("{}", rendered);
            }
        }
    } else {
        println!("{}", rendered);
    }

    println!("{}", "─".repeat(60).dimmed());
    println!("{} components: {}", "detected".dimmed(), sp.components.len());
    if exists {
        println!("{}", "⚠ scan will overwrite the existing manifest".yellow());
    }

    if !yes {
        print!("{} ", "Write manifest? [y/N]".bold());
        use std::io::Write;
        std::io::stdout().flush().ok();
        let mut input = String::new();
        if std::io::stdin().read_line(&mut input).is_err() {
            eprintln!("{}", "aborted".red());
            std::process::exit(1);
        }
        if !matches!(input.trim().to_lowercase().as_str(), "y" | "yes") {
            println!("{}", "aborted".dimmed());
            return;
        }
    }

    if let Err(e) = fs::create_dir_all(&project_dir) {
        eprintln!("{} {}", "✘".red(), e);
        std::process::exit(1);
    }
    if let Err(e) = fs::write(&project_toml, rendered) {
        eprintln!("{} {}", "✘".red(), e);
        std::process::exit(1);
    }
    println!("{} wrote {}", "✔".green(), project_toml.display());
}

fn list_env_files(project: &str) -> Vec<String> {
    let dir = projects_root().join(project).join("envs");
    let mut envs = Vec::new();
    if let Ok(entries) = fs::read_dir(&dir) {
        for e in entries.flatten() {
            if let Some(stem) = e.path().file_stem().and_then(|s| s.to_str()) {
                if e.path().extension().and_then(|x| x.to_str()) == Some("toml") {
                    envs.push(stem.to_string());
                }
            }
        }
    }
    envs.sort();
    envs
}

fn available_kube_contexts() -> Vec<String> {
    let mut names = Vec::new();
    let out = std::process::Command::new("kubectl")
        .args(["config", "get-contexts", "-o", "name"])
        .output();
    if let Ok(o) = out {
        if o.status.success() {
            for line in String::from_utf8_lossy(&o.stdout).lines() {
                let s = line.trim();
                if !s.is_empty() {
                    names.push(s.to_string());
                }
            }
        }
    }
    // Inclut aussi les aliases definis dans ~/.kube/.context_aliases
    if let Ok(home) = std::env::var("HOME") {
        let aliases_path = PathBuf::from(home).join(".kube").join(".context_aliases");
        if let Ok(content) = fs::read_to_string(&aliases_path) {
            for line in content.lines() {
                let trimmed = line.trim();
                if trimmed.is_empty() || trimmed.starts_with('#') {
                    continue;
                }
                if let Some((alias, _full)) = trimmed.split_once('=') {
                    let a = alias.trim();
                    if !a.is_empty() {
                        names.push(a.to_string());
                    }
                }
            }
        }
    }
    names
}

fn resolve_merged(project_name: &str, env: Option<&str>) -> Result<(Value, Option<String>), String> {
    let (layers, env_name) = build_layers(project_name, env)?;
    let (mut merged, _origins) = resolve(&layers);
    resolve_env_vars(&mut merged);
    derive_path(&mut merged);
    Ok((merged, env_name))
}

struct CheckReport {
    issues: u32,
    warnings: u32,
}

fn check_project(name: &str, kube_ctxs: &[String]) -> CheckReport {
    let mut report = CheckReport { issues: 0, warnings: 0 };
    println!();
    println!("{} {}", "▶".cyan(), name.bold());

    // Charge la config "base" (sans env) pour path + composants
    let (merged, _) = match resolve_merged(name, None) {
        Ok(x) => x,
        Err(e) => {
            println!("  {} {}", "✘".red(), e.red());
            report.issues += 1;
            return report;
        }
    };

    // 1. Path projet
    let path = merged.get("path").and_then(|v| v.as_str()).unwrap_or("");
    if path.is_empty() {
        println!("  {} path: non defini", "⚠".yellow());
        report.warnings += 1;
    } else if Path::new(path).is_dir() {
        println!("  {} path: {}", "✔".green(), path.dimmed());
    } else {
        println!("  {} path: {} (introuvable)", "✘".red(), path.red());
        report.issues += 1;
    }

    // 2. Composants
    let components_dir = merged
        .get("conventions")
        .and_then(|c| c.get("components_dir"))
        .and_then(|v| v.as_str())
        .unwrap_or("");
    if let Some(Value::Table(comps)) = merged.get("components") {
        for (cname, cval) in comps {
            let dir = cval.get("dir").and_then(|v| v.as_str()).unwrap_or(cname);
            let cpath = if let Some(p) = cval.get("path").and_then(|v| v.as_str()) {
                expand_path(p)
            } else if components_dir.is_empty() {
                format!("{}/{}", path, dir)
            } else {
                format!("{}/{}/{}", path, components_dir, dir)
            };
            if Path::new(&cpath).is_dir() {
                println!("  {} component {}", "✔".green(), cname.cyan());
            } else {
                println!("  {} component {} ({})", "✘".red(), cname.red(), cpath.dimmed());
                report.issues += 1;
            }
        }
    }

    // 3. Par env : kube.context
    let envs = list_env_files(name);
    if envs.is_empty() {
        println!("  {} no envs defined", "·".dimmed());
    } else {
        for env in &envs {
            let (env_merged, _) = match resolve_merged(name, Some(env)) {
                Ok(x) => x,
                Err(e) => {
                    println!("  {} env {}: {}", "✘".red(), env.red(), e);
                    report.issues += 1;
                    continue;
                }
            };
            let ctx = env_merged
                .get("kube")
                .and_then(|k| k.get("context"))
                .and_then(|v| v.as_str())
                .unwrap_or("");
            if ctx.is_empty() {
                println!("  {} env {}: kube.context vide", "⚠".yellow(), env.yellow());
                report.warnings += 1;
            } else if kube_ctxs.is_empty() {
                println!(
                    "  {} env {}: kube.context={} (non verifie — kubectl KO)",
                    "·".dimmed(),
                    env.cyan(),
                    ctx
                );
            } else if kube_ctxs.iter().any(|c| c == ctx) {
                println!("  {} env {}: kube.context={}", "✔".green(), env.cyan(), ctx);
            } else {
                println!(
                    "  {} env {}: kube.context={} (inconnu)",
                    "✘".red(),
                    env.red(),
                    ctx.red()
                );
                report.issues += 1;
            }
        }
    }

    report
}

fn run_doctor(name: Option<String>) {
    super::print_header("zproject doctor");
    let kube_ctxs = available_kube_contexts();
    if kube_ctxs.is_empty() {
        println!(
            "{}",
            "⚠ kubectl indisponible: verification des contexts desactivee"
                .yellow()
                .dimmed()
        );
    }

    let targets = match name {
        Some(n) => vec![n],
        None => list_projects(),
    };

    if targets.is_empty() {
        println!("{}", "No projects found.".yellow());
        return;
    }

    let mut total_issues = 0u32;
    let mut total_warnings = 0u32;
    for n in &targets {
        let r = check_project(n, &kube_ctxs);
        total_issues += r.issues;
        total_warnings += r.warnings;
    }

    println!();
    println!("{}", "─".repeat(60).dimmed());
    if total_issues == 0 && total_warnings == 0 {
        println!("{} tous les manifestes sont sains", "✔".green());
    } else {
        println!(
            "{} {} issue(s), {} warning(s)",
            if total_issues > 0 { "✘".red() } else { "⚠".yellow() },
            total_issues,
            total_warnings
        );
        if total_issues > 0 {
            std::process::exit(1);
        }
    }
}

fn run_list() {
    super::print_header("zproject list");
    let projects = list_projects();
    if projects.is_empty() {
        println!("{}", "No projects found.".yellow());
        return;
    }
    for name in projects {
        let path = projects_root().join(&name).join("project.toml");
        if let Some(v) = load_toml(&path) {
            let app = v.get("application").and_then(|x| x.as_str()).unwrap_or("?");
            let platform = v.get("platform").and_then(|x| x.as_str()).unwrap_or("-");
            let domain = v.get("domain").and_then(|x| x.as_str()).unwrap_or("-");
            println!(
                "  {}  {}  {}  {}",
                name.cyan().bold(),
                format!("app={}", app).dimmed(),
                format!("plat={}", platform).dimmed(),
                format!("dom={}", domain).dimmed()
            );
        } else {
            println!("  {}", name.cyan());
        }
    }
}

fn run_config(name: Option<String>, env: Option<String>, show_origin: bool) {
    let name = name
        .or_else(|| std::env::var("ZPROJECT_NAME").ok().filter(|s| !s.is_empty()))
        .unwrap_or_else(|| {
            let projects = list_projects();
            if projects.is_empty() {
                eprintln!("{}", "No projects found.".red());
                std::process::exit(1);
            }
            projects[0].clone()
        });
    // Si l'env n'est pas precise et qu'on a un projet actif, prefere ZPROJECT_ENV.
    let env = env.or_else(|| {
        if std::env::var("ZPROJECT_NAME").ok().as_deref() == Some(&name) {
            std::env::var("ZPROJECT_ENV").ok().filter(|s| !s.is_empty())
        } else {
            None
        }
    });

    let (layers, env_name) = match build_layers(&name, env.as_deref()) {
        Ok(x) => x,
        Err(e) => {
            eprintln!("{}", e.red());
            std::process::exit(1);
        }
    };

    let (mut merged, origins) = resolve(&layers);
    resolve_env_vars(&mut merged);
    derive_path(&mut merged);

    super::print_header("zproject config");
    println!("{} {}", "project:".dimmed(), name.cyan().bold());
    if let Some(e) = &env_name {
        println!("{} {}", "env:    ".dimmed(), e.cyan());
    }
    println!("{}", "─".repeat(60).dimmed());

    if show_origin {
        let mut leaves: Vec<(String, String, String)> = Vec::new();
        walk_leaves(&merged, String::new(), &mut |k, v| {
            let src = origins.get(k).cloned().unwrap_or_else(|| "?".into());
            let rendered = match v {
                Value::String(s) => format!("\"{}\"", s),
                other => other.to_string(),
            };
            leaves.push((k.to_string(), rendered, src));
        });
        leaves.sort();
        let key_width = leaves.iter().map(|(k, _, _)| k.len()).max().unwrap_or(0);
        for (k, v, src) in leaves {
            println!(
                "  {:<width$}  {}  {}",
                k.cyan(),
                v,
                format!("← {}", src).dimmed(),
                width = key_width
            );
        }
    } else {
        match toml::to_string_pretty(&merged) {
            Ok(s) => println!("{}", s),
            Err(_) => println!("{:#?}", merged),
        }
    }

    println!("{}", "─".repeat(60).dimmed());
    println!("{} {} layer(s)", "merged".dimmed(), layers.len());
    for l in &layers {
        println!("  {}", l.source.dimmed());
    }
}
