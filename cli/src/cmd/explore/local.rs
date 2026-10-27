// Scan des repos locaux sans lancer git : on lit .git/config directement.
use super::remote::{normalize_remote, Remote};
use std::path::{Path, PathBuf};

#[derive(Debug)]
pub struct LocalRepo {
    pub dir: PathBuf,
    pub rel: String,
    pub remote: Remote,
}

const MAX_DEPTH: usize = 8;

pub fn scan(work_dir: &Path, host: &str) -> Vec<LocalRepo> {
    let mut out = Vec::new();
    walk(work_dir, work_dir, host, 0, &mut out);
    out
}

fn walk(root: &Path, dir: &Path, host: &str, depth: usize, out: &mut Vec<LocalRepo>) {
    let git = dir.join(".git");
    if git.exists() {
        let remote = read_origin(&git).map_or(Remote::None, |u| normalize_remote(&u, host));
        let rel = dir.strip_prefix(root).unwrap_or(dir).to_string_lossy().into_owned();
        out.push(LocalRepo { dir: dir.to_path_buf(), rel, remote });
        return;
    }
    if depth >= MAX_DEPTH {
        return;
    }
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    for e in entries.flatten() {
        let name = e.file_name();
        let name = name.to_string_lossy();
        if name.starts_with('.') || name == "node_modules" {
            continue;
        }
        // file_type() ne suit pas les liens symboliques : evite les boucles
        if e.file_type().is_ok_and(|t| t.is_dir()) {
            walk(root, &e.path(), host, depth + 1, out);
        }
    }
}

/// `.git` est un dossier, ou un fichier `gitdir: <chemin>` (worktree/submodule).
pub fn read_origin(git_dir_or_file: &Path) -> Option<String> {
    let mut gd = git_dir_or_file.to_path_buf();
    if gd.is_file() {
        let txt = std::fs::read_to_string(&gd).ok()?;
        let target = txt.lines().find_map(|l| l.strip_prefix("gitdir:"))?.trim();
        gd = gd.parent()?.join(target);
    }
    if let Some(u) = std::fs::read_to_string(gd.join("config")).ok().and_then(|c| origin_url(&c)) {
        return Some(u);
    }
    // worktree : la config vit dans le depot commun
    let common = std::fs::read_to_string(gd.join("commondir")).ok()?;
    origin_url(&std::fs::read_to_string(gd.join(common.trim()).join("config")).ok()?)
}

fn origin_url(config: &str) -> Option<String> {
    let mut in_origin = false;
    for line in config.lines() {
        let l = line.trim();
        if l.starts_with('[') {
            in_origin = l.split_whitespace().collect::<Vec<_>>().join(" ") == "[remote \"origin\"]";
        } else if in_origin {
            if let Some((k, v)) = l.split_once('=') {
                if k.trim() == "url" {
                    return Some(v.trim().to_string());
                }
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static N: AtomicUsize = AtomicUsize::new(0);

    fn tmp() -> PathBuf {
        let d = std::env::temp_dir().join(format!(
            "zanvil-explore-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    fn repo(root: &Path, rel: &str, origin: Option<&str>) {
        let g = root.join(rel).join(".git");
        fs::create_dir_all(&g).unwrap();
        let cfg = origin
            .map(|u| format!("[core]\n\tbare = false\n[remote \"origin\"]\n\turl = {u}\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n"))
            .unwrap_or_else(|| "[core]\n\tbare = false\n".into());
        fs::write(g.join("config"), cfg).unwrap();
    }

    #[test]
    fn deux_repos_gitlab_et_foreign() {
        let d = tmp();
        repo(&d, "grp/a", Some("git@h.example:grp/a.git"));
        repo(&d, "misc/x", Some("https://github.com/o/x.git"));
        let mut r = scan(&d, "h.example");
        r.sort_by(|a, b| a.rel.cmp(&b.rel));
        assert_eq!(r.len(), 2);
        assert_eq!(r[0].rel, "grp/a");
        assert_eq!(r[0].dir, d.join("grp/a"));
        assert_eq!(r[0].remote, Remote::Gitlab("grp/a".into()));
        assert!(matches!(r[1].remote, Remote::Foreign(_)));
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn sans_remote() {
        let d = tmp();
        repo(&d, "grp/a", None);
        let r = scan(&d, "h.example");
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].remote, Remote::None);
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn ignore_node_modules_et_worktrees() {
        let d = tmp();
        repo(&d, "grp/a", None);
        repo(&d, "node_modules/dep", None);
        repo(&d, ".worktrees/r/b", None);
        repo(&d, "grp/.cache/z", None);
        let r = scan(&d, "h.example");
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].rel, "grp/a");
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn ne_descend_pas_dans_un_repo() {
        let d = tmp();
        repo(&d, "grp/a", None);
        repo(&d, "grp/a/vendor/sub", None);
        assert_eq!(scan(&d, "h.example").len(), 1);
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn git_fichier_gitdir() {
        let d = tmp();
        let real = d.join("grp/real.git");
        fs::create_dir_all(&real).unwrap();
        fs::write(real.join("config"), "[remote \"origin\"]\n\turl = git@h.example:grp/w.git\n").unwrap();
        let w = d.join("grp/w");
        fs::create_dir_all(&w).unwrap();
        fs::write(w.join(".git"), "gitdir: ../real.git\n").unwrap();
        let r = scan(&d, "h.example");
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].remote, Remote::Gitlab("grp/w".into()));
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn git_fichier_commondir() {
        let d = tmp();
        let main = d.join("main.git");
        fs::create_dir_all(main.join("worktrees/w")).unwrap();
        fs::write(main.join("config"), "[remote \"origin\"]\n\turl = git@h.example:grp/w.git\n").unwrap();
        fs::write(main.join("worktrees/w/commondir"), "../..\n").unwrap();
        let w = d.join("w");
        fs::create_dir_all(&w).unwrap();
        fs::write(w.join(".git"), format!("gitdir: {}\n", main.join("worktrees/w").display())).unwrap();
        assert_eq!(read_origin(&w.join(".git")).as_deref(), Some("git@h.example:grp/w.git"));
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn gitdir_absent_donne_none() {
        let d = tmp();
        let w = d.join("grp/w");
        fs::create_dir_all(&w).unwrap();
        fs::write(w.join(".git"), "gitdir: ../nope.git\n").unwrap();
        let r = scan(&d, "h.example");
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].remote, Remote::None);
        fs::remove_dir_all(&d).unwrap();
    }
}
