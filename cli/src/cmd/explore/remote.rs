// Normalisation des remotes git : on ne garde jamais d'identifiants.

#[derive(Debug, PartialEq)]
pub enum Remote {
    /// path_with_namespace sur l'hote GitLab configure
    Gitlab(String),
    /// URL sans identifiants, pour tout autre hote
    Foreign(String),
    None,
}

pub fn normalize_remote(url: &str, host: &str) -> Remote {
    let url = url.trim();
    if url.is_empty() {
        return Remote::None;
    }
    // (hote, chemin) selon la forme : scp `user@h:chemin` ou URL `scheme://[creds@]h[:port]/chemin`
    let (h, path) = if let Some((_, rest)) = url.split_once("://") {
        let (authority, path) = rest.split_once('/').unwrap_or((rest, ""));
        let authority = authority.rsplit('@').next().unwrap_or(authority);
        let h = authority.split(':').next().unwrap_or(authority);
        (h.to_string(), path.to_string())
    } else if let Some((left, path)) = url.split_once(':') {
        (left.rsplit('@').next().unwrap_or(left).to_string(), path.to_string())
    } else {
        return Remote::Foreign(url.to_string());
    };
    if !host.is_empty() && h.eq_ignore_ascii_case(host) {
        let p = path.trim_matches('/');
        let p = p.strip_suffix(".git").unwrap_or(p);
        return Remote::Gitlab(p.to_string());
    }
    // Foreign : on reconstruit sans identifiants (scp -> ssh:// n'est pas necessaire, on garde h:chemin)
    match url.split_once("://") {
        Some((scheme, _)) => Remote::Foreign(format!("{scheme}://{h}/{path}")),
        None => Remote::Foreign(format!("{h}:{path}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn gl(p: &str) -> Remote {
        Remote::Gitlab(p.to_string())
    }

    #[test]
    fn formes_gitlab() {
        assert_eq!(normalize_remote("git@h.example:grp/sub/repo.git", "h.example"), gl("grp/sub/repo"));
        assert_eq!(normalize_remote("ssh://git@h.example:2222/grp/repo.git", "h.example"), gl("grp/repo"));
        assert_eq!(normalize_remote("https://h.example/grp/repo.git", "h.example"), gl("grp/repo"));
        assert_eq!(normalize_remote("https://h.example/grp/repo", "h.example"), gl("grp/repo"));
    }

    #[test]
    fn identifiants_retires() {
        assert_eq!(normalize_remote("https://user:glpat-SECRET@h.example/grp/repo.git", "h.example"), gl("grp/repo"));
        assert_eq!(
            normalize_remote("https://user:tok@github.com/o/r.git", "h.example"),
            Remote::Foreign("https://github.com/o/r.git".to_string())
        );
    }

    #[test]
    fn vide() {
        assert_eq!(normalize_remote("", "h.example"), Remote::None);
    }
}
