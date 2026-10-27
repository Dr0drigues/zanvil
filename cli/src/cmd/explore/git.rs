// Operations git de l'explorateur : etat d'un depot et clone. Aucune sortie
// terminal (l'UI possede l'ecran), jamais d'invite : on rend donnees ou erreurs.
use std::path::Path;
use std::process::{Command, Stdio};

pub struct GitState {
    pub branch: String,
    pub dirty: bool,
    pub ahead: u32,
    pub behind: u32,
}

pub fn non_interactive(cmd: &mut Command) {
    cmd.env("GIT_TERMINAL_PROMPT", "0")
        .env("GIT_SSH_COMMAND", "ssh -o BatchMode=yes -o ConnectTimeout=15")
        .stdin(Stdio::null());
}

pub fn state(dir: &Path) -> Option<GitState> {
    let mut cmd = Command::new("git");
    // --no-optional-locks : pas de verrou d'index, sur en parallele d'un autre git
    cmd.arg("-C").arg(dir).args(["--no-optional-locks", "status", "--porcelain=v2", "--branch"]);
    non_interactive(&mut cmd);
    let out = cmd.output().ok().filter(|o| o.status.success())?;
    let text = String::from_utf8_lossy(&out.stdout);
    let mut st = GitState { branch: String::new(), dirty: false, ahead: 0, behind: 0 };
    for line in text.lines() {
        if let Some(b) = line.strip_prefix("# branch.head ") {
            st.branch = b.to_string();
        } else if let Some(ab) = line.strip_prefix("# branch.ab ") {
            let mut it = ab.split_whitespace().map(|n| n.trim_start_matches(['+', '-']).parse().unwrap_or(0));
            st.ahead = it.next().unwrap_or(0);
            st.behind = it.next().unwrap_or(0);
        } else if !line.starts_with('#') {
            st.dirty = true;
        }
    }
    Some(st)
}

pub fn clone(url: &str, dest: &Path) -> Result<(), String> {
    let existait = dest.exists();
    if existait && !dest.read_dir().map_or(false, |mut d| d.next().is_none()) {
        return Err(format!("existe déjà : {}", dest.display()));
    }
    if let Some(parent) = dest.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let mut cmd = Command::new("git");
    cmd.arg("clone").arg(url).arg(dest);
    non_interactive(&mut cmd);
    let out = cmd.output().map_err(|e| e.to_string())?;
    if out.status.success() {
        return Ok(());
    }
    if !existait {
        let _ = std::fs::remove_dir_all(dest);
    }
    let err = String::from_utf8_lossy(&out.stderr);
    Err(err.lines().rev().find(|l| !l.trim().is_empty()).unwrap_or("git clone a echoue").trim().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;

    // Git de test isole de la config globale de l'utilisateur.
    fn git(dir: &Path, args: &[&str]) {
        let st = Command::new("git")
            .arg("-C")
            .arg(dir)
            .args(["-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false"])
            .args(args)
            .env("GIT_CONFIG_GLOBAL", "/dev/null")
            .env("GIT_CONFIG_SYSTEM", "/dev/null")
            .status()
            .unwrap();
        assert!(st.success(), "git {args:?}");
    }

    fn tmp(name: &str) -> PathBuf {
        let p = std::env::temp_dir().join(format!("zanvil-git-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&p);
        fs::create_dir_all(&p).unwrap();
        p
    }

    fn repo(name: &str) -> PathBuf {
        let d = tmp(name);
        git(&d, &["init", "-q", "-b", "main"]);
        fs::write(d.join("f.txt"), "a").unwrap();
        git(&d, &["add", "."]);
        git(&d, &["commit", "-q", "-m", "init"]);
        d
    }

    #[test]
    fn state_propre_puis_sale() {
        let d = repo("state");
        let s = state(&d).unwrap();
        assert!(!s.dirty);
        assert_eq!(s.branch, "main");
        assert_eq!((s.ahead, s.behind), (0, 0));
        fs::write(d.join("f.txt"), "b").unwrap();
        assert!(state(&d).unwrap().dirty);
        assert!(state(&d.join("absent")).is_none());
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn clone_vers_chemin_neuf() {
        let src = repo("clone-src");
        let root = tmp("clone-dst");
        let dest = root.join("a/b/c");
        clone(&format!("file://{}", src.display()), &dest).unwrap();
        assert!(dest.join(".git").exists());
        // le clone suit l'amont : etat sans retard
        assert_eq!(state(&dest).unwrap().behind, 0);
        fs::remove_dir_all(&src).unwrap();
        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn clone_refuse_dossier_non_vide() {
        let src = repo("busy-src");
        let dest = tmp("busy-dst");
        fs::write(dest.join("keep.txt"), "x").unwrap();
        let e = clone(&format!("file://{}", src.display()), &dest).unwrap_err();
        assert!(e.contains("existe déjà"), "{e}");
        assert_eq!(fs::read_to_string(dest.join("keep.txt")).unwrap(), "x");
        fs::remove_dir_all(&src).unwrap();
        fs::remove_dir_all(&dest).unwrap();
    }

    #[test]
    fn clone_url_invalide_nettoie() {
        let root = tmp("bad");
        let dest = root.join("x/y");
        assert!(clone("file:///nexiste/pas/du/tout", &dest).is_err());
        assert!(!dest.exists());
        fs::remove_dir_all(&root).unwrap();
    }
}
