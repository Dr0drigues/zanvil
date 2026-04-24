use clap::{Args, ValueEnum};
use colored::*;
use regex::Regex;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};

#[derive(Clone, Debug, ValueEnum)]
pub enum Mode {
    /// Cherry-pick le commit HEAD sur chaque branche cible
    Cherry,
    /// Cherry-pick un range <from>..HEAD sur chaque branche cible
    Range,
    /// Capture le diff du worktree (staged+unstaged) et l'applique sur chaque branche cible
    Patch,
}

#[derive(Args, Debug)]
pub struct MrFanoutArgs {
    /// Strategie de propagation
    #[arg(value_enum, short, long, default_value = "cherry")]
    pub mode: Mode,
    /// Base du range (mode range uniquement)
    #[arg(long, default_value = "HEAD~1")]
    pub from: String,
    /// Branches cibles (repete). Si absent, selection interactive.
    #[arg(short, long)]
    pub target: Vec<String>,
    /// Selectionner toutes les branches matching sans prompt
    #[arg(long)]
    pub all: bool,
    /// Titre de la MR/PR
    #[arg(short = 'T', long)]
    pub title: Option<String>,
    /// Description de la MR/PR (texte direct)
    #[arg(short = 'D', long)]
    pub description: Option<String>,
    /// Description depuis un fichier
    #[arg(long, value_name = "PATH")]
    pub description_file: Option<String>,
    /// Prefix custom du nom de branche (default: git config user.name slugifie)
    #[arg(long)]
    pub branch_prefix: Option<String>,
    /// Ne pas push, uniquement creer les branches localement
    #[arg(long)]
    pub no_push: bool,
    /// Push sans creer de MR
    #[arg(long)]
    pub no_mr: bool,
    /// Afficher ce qui serait fait sans rien executer
    #[arg(short = 'n', long)]
    pub dry_run: bool,
    /// Creer la MR/PR en draft
    #[arg(long)]
    pub draft: bool,
    /// Arreter au premier echec (defaut: continuer et resumer a la fin)
    #[arg(long)]
    pub strict: bool,
    /// Fetch origin avant de creer les branches (met a jour les refs distantes)
    #[arg(long)]
    pub pull: bool,
    /// Mettre a jour les branches existantes (reset + reapply + force push, sans creer de MR)
    #[arg(long)]
    pub update: bool,
    /// Pattern regex custom pour la detection des branches d'env
    /// (defaut: devaz2|devaz|dev|qlfaz(-[a-z]+)?|qlf(-[a-z]+)?|ppaz|pprd|prodaz|prod)
    #[arg(long)]
    pub pattern: Option<String>,
}

const DEFAULT_PATTERN: &str = r"^(devaz2|devaz|dev|qlfaz(-[a-z]+)?|qlf(-[a-z]+)?|ppaz|pprd|prodaz|prod)$";
const FORBIDDEN_KEYWORDS: &[&str] = &["feature", "fix", "hotfix", "release", "feat", "chore"];

#[derive(Debug, Clone)]
enum Provider {
    Github,
    Gitlab,
}

struct Outcome {
    target: String,
    branch: String,
    status: StepStatus,
    message: String,
}

enum StepStatus {
    Ok,
    Skipped,
    Failed,
}

pub fn run(args: MrFanoutArgs) {
    super::print_header("mr fanout");

    if let Err(e) = ensure_in_git_repo() {
        die(&e);
    }

    let provider = match detect_provider() {
        Ok(p) => p,
        Err(e) => die(&e),
    };
    println!(
        "{} {}",
        "provider:".dimmed(),
        match provider {
            Provider::Github => "github (gh)".cyan(),
            Provider::Gitlab => "gitlab (glab)".cyan(),
        }
    );

    let original_branch = match git_current_branch() {
        Some(b) => b,
        None => die("HEAD detached, abort. Switch sur une branche d'abord."),
    };
    println!("{} {}", "current:  ".dimmed(), original_branch.cyan());

    let pattern_str = args.pattern.as_deref().unwrap_or(DEFAULT_PATTERN);
    let pattern = match Regex::new(pattern_str) {
        Ok(r) => r,
        Err(e) => die(&format!("Pattern regex invalide: {}", e)),
    };

    // Fetch d'abord pour avoir des refs a jour
    if !args.dry_run {
        print!("{} ", "fetching origin...".dimmed());
        std::io::stdout().flush().ok();
        let _ = run_cmd("git", &["fetch", "--prune", "origin"]);
        println!("{}", "ok".green());
    }

    let candidates = list_env_branches(&pattern);
    if candidates.is_empty() {
        die(&format!(
            "Aucune branche distante ne matche le pattern {}",
            pattern_str
        ));
    }

    let targets = if !args.target.is_empty() {
        // Validation: tous les targets fournis doivent exister
        let mut sel = Vec::new();
        for t in &args.target {
            if candidates.contains(t) {
                sel.push(t.clone());
            } else {
                eprintln!("{} branche cible '{}' introuvable (origin)", "✘".red(), t);
                std::process::exit(1);
            }
        }
        sel
    } else if args.all {
        candidates.clone()
    } else {
        match select_targets_interactive(&candidates) {
            Some(t) => t,
            None => {
                println!("{}", "aucune cible selectionnee, abandon".dimmed());
                return;
            }
        }
    };

    if targets.is_empty() {
        die("aucune cible.");
    }

    println!(
        "{} {}",
        "targets:  ".dimmed(),
        targets.join(", ").cyan()
    );

    // Title
    let title = match args.title.clone() {
        Some(t) if !t.trim().is_empty() => t,
        _ => match prompt_line("Titre de la MR") {
            Some(t) if !t.trim().is_empty() => t,
            _ => die("Titre requis."),
        },
    };

    // Slug
    let slug = slugify(&title);
    if slug.is_empty() {
        die("Titre vide apres slugification.");
    }
    if let Err(e) = ensure_no_forbidden(&slug) {
        die(&e);
    }

    // Description
    let description = resolve_description(&args, &title);

    // Branch prefix
    let prefix = match args.branch_prefix.clone() {
        Some(p) => slugify(&p),
        None => match git_user_slug() {
            Some(u) => u,
            None => die("Impossible de deriver le prefix (git config user.name vide). Utiliser --branch-prefix."),
        },
    };
    if let Err(e) = ensure_no_forbidden(&prefix) {
        die(&e);
    }

    // Affichage du plan
    println!();
    println!("{}", "─".repeat(60).dimmed());
    println!("{} {}", "title:".dimmed(), title.bold());
    println!("{} {}", "slug: ".dimmed(), slug.cyan());
    println!("{} {}", "mode: ".dimmed(), format!("{:?}", args.mode).to_lowercase().cyan());
    if matches!(args.mode, Mode::Range) {
        println!("{} {}", "from: ".dimmed(), args.from.cyan());
    }
    println!("{}", "─".repeat(60).dimmed());
    for t in &targets {
        let new_branch = format!("{}_{}_{}", prefix, t, slug);
        let mr_title = format!("[{}] {}", env_label(t), title);
        if args.update {
            if branch_exists_remote(&new_branch) {
                println!(
                    "  {} {} {} {}",
                    "↻".cyan(),
                    t.cyan(),
                    "update".dimmed(),
                    new_branch.yellow()
                );
            } else {
                println!(
                    "  {} {} {} {}",
                    "–".dimmed(),
                    t.dimmed(),
                    "skip (branche distante absente):".dimmed(),
                    new_branch.dimmed()
                );
            }
        } else {
            println!(
                "  {} {} {} {}",
                "→".dimmed(),
                t.cyan(),
                "as".dimmed(),
                new_branch.green()
            );
            println!("    {} {}", "MR:".dimmed(), mr_title.bold());
        }
    }
    println!("{}", "─".repeat(60).dimmed());

    if args.dry_run {
        println!("{} dry-run, rien execute", "·".dimmed());
        return;
    }

    if !confirm("Continuer ?", true) {
        println!("{}", "annule".dimmed());
        return;
    }

    // Fetch origin pour mettre a jour les refs distantes avant de creer les branches
    if args.pull {
        print!("{} git fetch origin... ", "·".dimmed());
        let r = run_cmd("git", &["fetch", "origin"]);
        if r.ok {
            println!("{}", "ok".green());
        } else {
            println!("{}", "warn: fetch failed, on continue".yellow());
        }
    }

    // Mode patch : capturer le diff + stash
    let patch_path = if matches!(args.mode, Mode::Patch) {
        match capture_worktree_patch() {
            Ok(p) => p,
            Err(e) => die(&e),
        }
    } else {
        // Working dir doit etre clean
        if !is_worktree_clean() {
            die("Working tree dirty. Commit/stash d'abord, ou utilisez --mode patch.");
        }
        PathBuf::new()
    };

    let stashed = if matches!(args.mode, Mode::Patch) {
        match stash_worktree() {
            Ok(b) => b,
            Err(e) => die(&e),
        }
    } else {
        false
    };

    // Capture le SHA HEAD pour cherry-pick (avant tout switch)
    let head_sha = git_rev_parse("HEAD").unwrap_or_else(|_| die("git rev-parse HEAD a echoue"));
    let from_sha = if matches!(args.mode, Mode::Range) {
        match git_rev_parse(&args.from) {
            Ok(s) => Some(s),
            Err(e) => {
                let _ = restore_state(&original_branch, stashed);
                die(&format!("git rev-parse {} a echoue: {}", args.from, e));
            }
        }
    } else {
        None
    };

    let mut outcomes: Vec<Outcome> = Vec::new();

    for target in &targets {
        let new_branch = format!("{}_{}_{}", prefix, target, slug);
        println!();
        println!(
            "{} {} {}",
            "▶".cyan(),
            target.bold(),
            format!("→ {}", new_branch).dimmed()
        );

        let mr_title = format!("[{}] {}", env_label(target), &title);
        let outcome = process_target(
            target,
            &new_branch,
            &args,
            &provider,
            &patch_path,
            &head_sha,
            from_sha.as_deref(),
            &mr_title,
            &description,
        );

        let stop = args.strict && matches!(outcome.status, StepStatus::Failed);
        outcomes.push(outcome);
        if stop {
            eprintln!("{}", "strict mode: arret au premier echec".red());
            break;
        }
    }

    // Restore
    if let Err(e) = restore_state(&original_branch, stashed) {
        eprintln!("{} {}", "✘".red(), e);
    }
    if matches!(args.mode, Mode::Patch) {
        let _ = std::fs::remove_file(&patch_path);
    }

    // Summary
    println!();
    println!("{}", "─".repeat(60).dimmed());
    println!("{}", "Summary".bold());
    let mut ok = 0;
    let mut fail = 0;
    let mut skip = 0;
    for o in &outcomes {
        let (sym, color) = match o.status {
            StepStatus::Ok => {
                ok += 1;
                ("✔", "green")
            }
            StepStatus::Skipped => {
                skip += 1;
                ("·", "dim")
            }
            StepStatus::Failed => {
                fail += 1;
                ("✘", "red")
            }
        };
        let symbol = match color {
            "green" => sym.green(),
            "red" => sym.red(),
            _ => sym.dimmed(),
        };
        println!(
            "  {} {:<14} {:<40} {}",
            symbol,
            o.target.cyan(),
            o.branch.dimmed(),
            o.message
        );
    }
    println!("{}", "─".repeat(60).dimmed());
    println!(
        "{} ok  {} skip  {} fail",
        ok.to_string().green(),
        skip.to_string().dimmed(),
        fail.to_string().red()
    );

    if fail > 0 {
        std::process::exit(1);
    }
}

fn process_target(
    target: &str,
    new_branch: &str,
    args: &MrFanoutArgs,
    provider: &Provider,
    patch_path: &std::path::Path,
    head_sha: &str,
    from_sha: Option<&str>,
    title: &str,
    description: &str,
) -> Outcome {
    // 1. Positionnement sur la branche de travail
    let r = if args.update {
        // Mode update : la branche doit exister sur origin (MR deja ouverte)
        if !branch_exists_remote(new_branch) {
            return Outcome {
                target: target.into(), branch: new_branch.into(),
                status: StepStatus::Skipped,
                message: "branche distante absente — MR non existante, utiliser sans --update".into(),
            };
        }
        if branch_exists_local(new_branch) {
            let s = run_cmd("git", &["switch", new_branch]);
            if !s.ok {
                return Outcome {
                    target: target.into(), branch: new_branch.into(),
                    status: StepStatus::Failed,
                    message: format!("switch failed: {}", s.stderr.trim()),
                };
            }
            run_cmd("git", &["reset", "--hard", &format!("origin/{}", target)])
        } else {
            // Branche sur origin mais pas locale — checkout depuis origin
            run_cmd("git", &["switch", "-c", new_branch, &format!("origin/{}", new_branch)])
        }
    } else {
        // Mode normal : la branche ne doit pas exister
        if branch_exists_local(new_branch) {
            return Outcome {
                target: target.into(), branch: new_branch.into(),
                status: StepStatus::Skipped,
                message: "branche locale deja existante (utiliser --update pour ecraser)".into(),
            };
        }
        run_cmd("git", &["switch", "-c", new_branch, &format!("origin/{}", target)])
    };
    if !r.ok {
        return Outcome {
            target: target.into(),
            branch: new_branch.into(),
            status: StepStatus::Failed,
            message: format!("switch/reset failed: {}", r.stderr.trim()),
        };
    }

    // 3. Apply changes
    let apply_result = match args.mode {
        Mode::Cherry => apply_cherry(head_sha),
        Mode::Range => apply_range(from_sha.unwrap(), head_sha),
        Mode::Patch => apply_patch(patch_path, title),
    };

    if let Err(e) = apply_result {
        // Rollback : abort eventuel + delete branch
        let _ = run_cmd("git", &["cherry-pick", "--abort"]);
        let _ = run_cmd("git", &["am", "--abort"]);
        let _ = run_cmd("git", &["reset", "--hard", "HEAD"]);
        // Switch back se fait par restore_state, mais on doit jeter la branche cassee
        return Outcome {
            target: target.into(),
            branch: new_branch.into(),
            status: StepStatus::Failed,
            message: format!("apply failed: {}", e),
        };
    }

    // 4. Push
    if args.no_push {
        return Outcome {
            target: target.into(),
            branch: new_branch.into(),
            status: StepStatus::Ok,
            message: "branche creee (no-push)".into(),
        };
    }

    let push_args: Vec<&str> = if args.update {
        vec!["push", "--force-with-lease", "origin", new_branch]
    } else {
        vec!["push", "-u", "origin", new_branch]
    };
    let r = run_cmd("git", &push_args);
    if !r.ok {
        return Outcome {
            target: target.into(),
            branch: new_branch.into(),
            status: StepStatus::Failed,
            message: format!("push failed: {}", r.stderr.trim()),
        };
    }

    // En mode update la MR existe deja, le push suffit a la mettre a jour
    if args.update {
        return Outcome {
            target: target.into(),
            branch: new_branch.into(),
            status: StepStatus::Ok,
            message: "branche mise a jour (force push)".into(),
        };
    }

    if args.no_mr {
        return Outcome {
            target: target.into(),
            branch: new_branch.into(),
            status: StepStatus::Ok,
            message: "pushed (no-mr)".into(),
        };
    }

    // 5. MR/PR
    let mr_url = match provider {
        Provider::Github => create_github_pr(new_branch, target, title, description, args.draft),
        Provider::Gitlab => create_gitlab_mr(new_branch, target, title, description, args.draft),
    };

    match mr_url {
        Ok(url) => Outcome {
            target: target.into(),
            branch: new_branch.into(),
            status: StepStatus::Ok,
            message: url,
        },
        Err(e) => Outcome {
            target: target.into(),
            branch: new_branch.into(),
            status: StepStatus::Failed,
            message: format!("mr create failed: {}", e),
        },
    }
}

fn apply_cherry(sha: &str) -> Result<(), String> {
    let r = run_cmd("git", &["cherry-pick", sha]);
    if r.ok {
        Ok(())
    } else {
        Err(r.stderr.trim().to_string())
    }
}

fn apply_range(from: &str, to: &str) -> Result<(), String> {
    let range = format!("{}..{}", from, to);
    let r = run_cmd("git", &["cherry-pick", &range]);
    if r.ok {
        Ok(())
    } else {
        Err(r.stderr.trim().to_string())
    }
}

fn apply_patch(patch_path: &std::path::Path, title: &str) -> Result<(), String> {
    if !patch_path.exists() {
        return Err("patch introuvable".into());
    }
    // Tente git apply (binary + 3way)
    let r = run_cmd(
        "git",
        &[
            "apply",
            "--3way",
            "--whitespace=nowarn",
            patch_path.to_str().unwrap(),
        ],
    );
    if !r.ok {
        return Err(format!("git apply: {}", r.stderr.trim()));
    }
    let r = run_cmd("git", &["add", "-A"]);
    if !r.ok {
        return Err(format!("git add: {}", r.stderr.trim()));
    }
    let r = run_cmd("git", &["commit", "-m", title]);
    if !r.ok {
        return Err(format!("git commit: {}", r.stderr.trim()));
    }
    Ok(())
}

fn capture_worktree_patch() -> Result<PathBuf, String> {
    // Stage tout (y compris untracked) pour obtenir un diff complet, puis unstage.
    // Les fichiers restent intacts sur disque apres git reset HEAD.
    let add_r = run_cmd("git", &["add", "--all"]);
    if !add_r.ok {
        return Err(format!("git add: {}", add_r.stderr.trim()));
    }
    let diff_r = Command::new("git")
        .args(["diff", "--cached", "HEAD", "--binary"])
        .output()
        .map_err(|e| format!("git diff: {}", e));
    // Toujours unstager, meme en cas d'erreur
    let _ = run_cmd("git", &["reset", "HEAD"]);
    let diff_r = diff_r?;
    if !diff_r.status.success() {
        return Err(String::from_utf8_lossy(&diff_r.stderr).to_string());
    }
    if diff_r.stdout.is_empty() {
        return Err("aucun changement dans le worktree".into());
    }
    let path = std::env::temp_dir().join(format!("mr-fanout-{}.patch", std::process::id()));
    std::fs::write(&path, &diff_r.stdout).map_err(|e| format!("write patch: {}", e))?;
    Ok(path)
}

fn stash_worktree() -> Result<bool, String> {
    if is_worktree_clean() {
        return Ok(false);
    }
    let r = run_cmd(
        "git",
        &["stash", "push", "-u", "-m", "mr-fanout temporary stash"],
    );
    if !r.ok {
        return Err(format!("stash failed: {}", r.stderr.trim()));
    }
    Ok(true)
}

fn restore_state(original_branch: &str, stashed: bool) -> Result<(), String> {
    let r = run_cmd("git", &["switch", original_branch]);
    if !r.ok {
        return Err(format!(
            "switch back to {} failed: {}",
            original_branch,
            r.stderr.trim()
        ));
    }
    if stashed {
        let r = run_cmd("git", &["stash", "pop"]);
        if !r.ok {
            return Err(format!("stash pop failed: {}", r.stderr.trim()));
        }
    }
    Ok(())
}

fn is_worktree_clean() -> bool {
    let r = Command::new("git")
        .args(["status", "--porcelain"])
        .output();
    match r {
        Ok(o) => o.stdout.is_empty(),
        Err(_) => false,
    }
}

fn branch_exists_local(name: &str) -> bool {
    let r = Command::new("git")
        .args(["show-ref", "--verify", "--quiet", &format!("refs/heads/{}", name)])
        .status();
    matches!(r, Ok(s) if s.success())
}

fn branch_exists_remote(name: &str) -> bool {
    let r = Command::new("git")
        .args(["ls-remote", "--exit-code", "--heads", "origin", name])
        .output();
    matches!(r, Ok(o) if o.status.success())
}

fn ensure_in_git_repo() -> Result<(), String> {
    let r = Command::new("git")
        .args(["rev-parse", "--is-inside-work-tree"])
        .output()
        .map_err(|e| format!("git: {}", e))?;
    if !r.status.success() {
        return Err("Pas dans un repo Git.".into());
    }
    Ok(())
}

fn detect_provider() -> Result<Provider, String> {
    let r = Command::new("git")
        .args(["remote", "get-url", "origin"])
        .output()
        .map_err(|e| format!("git remote: {}", e))?;
    if !r.status.success() {
        return Err("Pas de remote 'origin'.".into());
    }
    let url = String::from_utf8_lossy(&r.stdout).trim().to_lowercase();
    if url.contains("github.com") {
        if !command_exists("gh") {
            return Err("github detecte mais 'gh' introuvable. brew install gh".into());
        }
        Ok(Provider::Github)
    } else if url.contains("gitlab") {
        if !command_exists("glab") {
            return Err("gitlab detecte mais 'glab' introuvable. brew install glab".into());
        }
        Ok(Provider::Gitlab)
    } else {
        Err(format!("Provider inconnu pour l'URL: {}", url))
    }
}

fn command_exists(name: &str) -> bool {
    Command::new("which")
        .arg(name)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn git_current_branch() -> Option<String> {
    let r = Command::new("git")
        .args(["branch", "--show-current"])
        .output()
        .ok()?;
    if !r.status.success() {
        return None;
    }
    let s = String::from_utf8_lossy(&r.stdout).trim().to_string();
    if s.is_empty() {
        None
    } else {
        Some(s)
    }
}

fn git_rev_parse(rev: &str) -> Result<String, String> {
    let r = Command::new("git")
        .args(["rev-parse", rev])
        .output()
        .map_err(|e| e.to_string())?;
    if !r.status.success() {
        return Err(String::from_utf8_lossy(&r.stderr).trim().to_string());
    }
    Ok(String::from_utf8_lossy(&r.stdout).trim().to_string())
}

fn git_user_slug() -> Option<String> {
    let r = Command::new("git")
        .args(["config", "--get", "user.name"])
        .output()
        .ok()?;
    if !r.status.success() {
        return None;
    }
    let s = String::from_utf8_lossy(&r.stdout).trim().to_string();
    if s.is_empty() {
        return None;
    }
    Some(slugify(&s))
}

fn list_env_branches(pattern: &Regex) -> Vec<String> {
    let r = match Command::new("git")
        .args(["for-each-ref", "--format=%(refname:short)", "refs/remotes/origin"])
        .output()
    {
        Ok(o) => o,
        Err(_) => return Vec::new(),
    };
    if !r.status.success() {
        return Vec::new();
    }
    let mut out = Vec::new();
    for line in String::from_utf8_lossy(&r.stdout).lines() {
        let s = line.trim();
        if s.is_empty() {
            continue;
        }
        // Strip "origin/" prefix
        let name = match s.strip_prefix("origin/") {
            Some(n) => n,
            None => s,
        };
        if name == "HEAD" {
            continue;
        }
        if pattern.is_match(name) {
            out.push(name.to_string());
        }
    }
    out.sort();
    out.dedup();
    out
}

fn select_targets_interactive(candidates: &[String]) -> Option<Vec<String>> {
    if !command_exists("fzf") {
        // Fallback texte
        println!();
        println!("{}", "Branches detectees:".bold());
        for (i, b) in candidates.iter().enumerate() {
            println!("  {} {}", format!("{:>2}.", i + 1).dimmed(), b);
        }
        let line = prompt_line("Indices separes par des virgules (ou 'all', vide=annuler)")?;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            return None;
        }
        if trimmed.eq_ignore_ascii_case("all") {
            return Some(candidates.to_vec());
        }
        let mut sel = Vec::new();
        for tok in trimmed.split(|c: char| c == ',' || c.is_whitespace()) {
            if tok.is_empty() {
                continue;
            }
            match tok.parse::<usize>() {
                Ok(n) if n >= 1 && n <= candidates.len() => sel.push(candidates[n - 1].clone()),
                _ => {
                    eprintln!("indice invalide: {}", tok);
                    return None;
                }
            }
        }
        return Some(sel);
    }

    let input = candidates.join("\n");
    let mut child = Command::new("fzf")
        .args([
            "--multi",
            "--height=40%",
            "--reverse",
            "--prompt=targets> ",
            "--header=TAB pour multi-select, ENTER pour valider",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .ok()?;
    {
        let stdin = child.stdin.as_mut()?;
        stdin.write_all(input.as_bytes()).ok()?;
    }
    let out = child.wait_with_output().ok()?;
    if !out.status.success() {
        return None;
    }
    let sel: Vec<String> = String::from_utf8_lossy(&out.stdout)
        .lines()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();
    if sel.is_empty() {
        None
    } else {
        Some(sel)
    }
}

/// Derive le label d'environnement depuis le nom de branche cible.
/// Ex: devaz2 → DEV-UNSTABLE, qlfaz-b → QLF-B, ppaz → PREPROD
fn env_label(branch: &str) -> String {
    if branch == "devaz2" {
        return "DEV-UNSTABLE".into();
    }
    if branch == "devaz" || branch == "dev" {
        return "DEV".into();
    }
    if branch == "ppaz" || branch == "pprd" {
        return "PREPROD".into();
    }
    if branch == "prodaz" || branch == "prod" {
        return "PROD".into();
    }
    for prefix in &["qlfaz", "qlf"] {
        if let Some(rest) = branch.strip_prefix(prefix) {
            return if rest.is_empty() {
                "QLF".into()
            } else if let Some(suf) = rest.strip_prefix('-') {
                format!("QLF-{}", suf.to_uppercase())
            } else {
                "QLF".into()
            };
        }
    }
    branch.to_uppercase()
}

fn resolve_description(args: &MrFanoutArgs, title: &str) -> String {
    if let Some(d) = &args.description {
        return d.clone();
    }
    if let Some(p) = &args.description_file {
        return std::fs::read_to_string(p).unwrap_or_else(|e| die(&format!("read {}: {}", p, e)));
    }
    // Edition interactive via $EDITOR
    let editor = std::env::var("EDITOR").unwrap_or_else(|_| "vi".into());
    let path = std::env::temp_dir().join(format!("mr-fanout-desc-{}.md", std::process::id()));
    let template = format!(
        "{}\n\n# Description (les lignes commencant par # seront ignorees)\n# Titre: {}\n",
        "", title
    );
    std::fs::write(&path, template).ok();
    let status = Command::new(&editor).arg(&path).status();
    if status.map(|s| !s.success()).unwrap_or(true) {
        die("editeur ferme avec erreur");
    }
    let mut buf = String::new();
    std::fs::File::open(&path)
        .and_then(|mut f| f.read_to_string(&mut buf))
        .ok();
    let _ = std::fs::remove_file(&path);
    let cleaned: String = buf
        .lines()
        .filter(|l| !l.trim_start().starts_with('#'))
        .collect::<Vec<_>>()
        .join("\n");
    cleaned.trim().to_string()
}

fn create_github_pr(
    head: &str,
    base: &str,
    title: &str,
    body: &str,
    draft: bool,
) -> Result<String, String> {
    let mut args: Vec<&str> = vec![
        "pr", "create", "--base", base, "--head", head, "--title", title, "--body", body,
    ];
    if draft {
        args.push("--draft");
    }
    let r = Command::new("gh")
        .args(&args)
        .output()
        .map_err(|e| format!("gh: {}", e))?;
    if !r.status.success() {
        return Err(String::from_utf8_lossy(&r.stderr).trim().to_string());
    }
    Ok(String::from_utf8_lossy(&r.stdout).trim().to_string())
}

fn create_gitlab_mr(
    source: &str,
    target: &str,
    title: &str,
    description: &str,
    draft: bool,
) -> Result<String, String> {
    let title_owned;
    let title_eff: &str = if draft && !title.starts_with("Draft:") {
        title_owned = format!("Draft: {}", title);
        title_owned.as_str()
    } else {
        title
    };
    let mut args: Vec<&str> = vec![
        "mr",
        "create",
        "--source-branch",
        source,
        "--target-branch",
        target,
        "--title",
        title_eff,
        "--description",
        description,
        "--remove-source-branch",
        "--squash-before-merge",
        "--yes",
    ];
    if draft {
        args.push("--draft");
    }
    let r = Command::new("glab")
        .args(&args)
        .output()
        .map_err(|e| format!("glab: {}", e))?;
    if !r.status.success() {
        return Err(String::from_utf8_lossy(&r.stderr).trim().to_string());
    }
    // glab affiche l'URL de la MR sur stdout/stderr selon les versions
    let stdout = String::from_utf8_lossy(&r.stdout).to_string();
    let stderr = String::from_utf8_lossy(&r.stderr).to_string();
    let url = stdout
        .lines()
        .chain(stderr.lines())
        .find(|l| l.contains("http"))
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| "MR creee".into());
    Ok(url)
}

fn slugify(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut last_dash = false;
    for c in s.chars() {
        if c.is_ascii_alphanumeric() {
            for lc in c.to_lowercase() {
                out.push(lc);
            }
            last_dash = false;
        } else if !last_dash && !out.is_empty() {
            out.push('-');
            last_dash = true;
        }
    }
    out.trim_end_matches('-').to_string()
}

fn ensure_no_forbidden(s: &str) -> Result<(), String> {
    let lower = s.to_lowercase();
    for kw in FORBIDDEN_KEYWORDS {
        // Cherche le mot complet (precede/suivi de '-' ou bord)
        let pat = format!(r"(^|[-_/]){}([-_/]|$)", regex::escape(kw));
        if Regex::new(&pat).unwrap().is_match(&lower) {
            return Err(format!(
                "'{}' contient le mot interdit '{}' (CI sensible)",
                s, kw
            ));
        }
    }
    Ok(())
}

fn prompt_line(label: &str) -> Option<String> {
    print!("{} ", format!("{}:", label).bold());
    std::io::stdout().flush().ok();
    let mut buf = String::new();
    std::io::stdin().read_line(&mut buf).ok()?;
    Some(buf.trim_end_matches(['\n', '\r']).to_string())
}

fn confirm(label: &str, default_yes: bool) -> bool {
    let suffix = if default_yes { "[Y/n]" } else { "[y/N]" };
    print!("{} {} ", label.bold(), suffix.dimmed());
    std::io::stdout().flush().ok();
    let mut buf = String::new();
    if std::io::stdin().read_line(&mut buf).is_err() {
        return false;
    }
    let s = buf.trim().to_lowercase();
    if s.is_empty() {
        return default_yes;
    }
    matches!(s.as_str(), "y" | "yes" | "o" | "oui")
}

struct CmdResult {
    ok: bool,
    stderr: String,
    #[allow(dead_code)]
    stdout: String,
}

fn run_cmd(prog: &str, args: &[&str]) -> CmdResult {
    match Command::new(prog).args(args).output() {
        Ok(o) => CmdResult {
            ok: o.status.success(),
            stderr: String::from_utf8_lossy(&o.stderr).into_owned(),
            stdout: String::from_utf8_lossy(&o.stdout).into_owned(),
        },
        Err(e) => CmdResult {
            ok: false,
            stderr: e.to_string(),
            stdout: String::new(),
        },
    }
}

fn die(msg: &str) -> ! {
    eprintln!("{} {}", "✘".red(), msg.red());
    std::process::exit(1);
}
