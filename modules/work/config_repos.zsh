# ==============================================================================
# Work Config Repos — creation et mise aux normes des repos de configuration
# ==============================================================================
# Spec : web/docs/superpowers/specs/2026-08-07-work-config-repos-design.md
#
# Le coeur de ce fichier est `_work_cfg_build_plan` : une fonction pure qui recoit
# l etat d un repo et rend une liste d actions. Tout le reste — collecte, rendu,
# application — est mince autour d elle, et c est delibere : la norme est la seule
# chose qui merite d etre testee, et elle ne doit pas dependre du reseau pour l etre.

# --- Norme, en dur (surchargeable au runtime par --envs, jamais persistee) ---

typeset -ga _WORK_CFG_ENVS_ALL=(dev qlf pprd prd)
typeset -ga _WORK_CFG_ENVS_PROTECTED=(pprd prd)
typeset -ga _WORK_CFG_BU_ALL=(blg edt udb tsc shared)
typeset -g  _WORK_CFG_PUSH_LEVEL=40      # Maintainers
typeset -g  _WORK_CFG_MERGE_LEVEL=40     # Maintainers

# --- Chemin canonique ---

# Decompose un chemin absolu en bu/app/repo.
# Usage : _work_cfg_parse_path <chemin>
# Sortie : "<bu>\t<app>\t<repo>". Return 1 si le chemin ne suit pas la forme
#          $WORK_DIR/<bu>/applications/<app>/configurations/<repo>.
#
# L arite stricte a cinq segments ecarte d elle-meme les chemins sous companion/,
# qui en comptent six. Le message dedie est rendu par _work_cfg_guard_target.
_work_cfg_parse_path() {
    local p="${1:-}"
    local root="${WORK_DIR:-$HOME/work}"
    [[ -n "$p" && "$p" == "$root"/* ]] || return 1

    local rel="${p#$root/}"
    local -a parts
    parts=(${(s:/:)rel})

    # Cinq segments pour un repo, six pour un sous-groupe companion. Ce dernier est
    # hors perimetre, mais il doit etre RECONNU pour que _work_cfg_guard_target puisse
    # le dire. Le refuser ici par l arite renverrait « BU inconnue » a quelqu un dont
    # la BU est parfaitement valide — le message nommerait le mauvais probleme.
    local repo
    case ${#parts} in
        5) repo="$parts[5]" ;;
        6) [[ "$parts[5]" == companion ]] || return 1
           repo="companion/$parts[6]" ;;
        *) return 1 ;;
    esac
    [[ "$parts[2]" == applications ]] || return 1
    [[ "$parts[4]" == configurations ]] || return 1
    (( ${_WORK_CFG_BU_ALL[(Ie)$parts[1]]} )) || return 1

    print -r -- "$parts[1]	$parts[3]	$repo"
    return 0
}

# --- Refus durs ---

# Refuse une cible hors perimetre. Aucun appel reseau, jamais.
# Usage : _work_cfg_guard_target <bu> <app> <repo>
_work_cfg_guard_target() {
    local bu="${1:-}" app="${2:-}" repo="${3:-}"

    if ! (( ${_WORK_CFG_BU_ALL[(Ie)$bu]} )); then
        _ui_msg_fail "BU inconnue : « ${bu:-<vide>} » (attendu : ${_WORK_CFG_BU_ALL})"
        return 1
    fi
    if [[ -z "$app" ]]; then
        _ui_msg_fail "application non determinee — passer --app, ou se placer dans le chemin canonique"
        return 1
    fi
    if [[ -z "$repo" ]]; then
        _ui_msg_fail "repo non determine — le passer en argument, ou se placer dans le chemin canonique"
        return 1
    fi
    # technical-assets appartient a une autre chaine de responsabilite et n a pas la
    # topologie de la norme : l auditer produirait des ecarts qu il ne faut pas corriger.
    if [[ "$repo" == technical-assets ]]; then
        _ui_msg_fail "technical-assets est hors perimetre — ni ecriture, ni audit"
        return 1
    fi
    # `companion` seul designe le sous-groupe, pas un projet. Quelqu un debout dans
    # configurations/companion obtiendrait ce nom par deduction et auditerait un groupe
    # comme s il etait un depot : la lecture 404 et la creation entrerait en collision
    # avec le sous-groupe existant. On le dit, et on indique ou descendre.
    if [[ "$repo" == companion ]]; then
        _ui_msg_fail "companion est un sous-groupe, pas un repo"
        _ui_msg_info "descendre dans l un de ses projets, ou le nommer : companion/<repo>"
        return 1
    fi
    # Un repo peut vivre dans un sous-groupe : configurations/companion/{app,api,loader}
    # en sont, et ils portent la meme topologie que les autres — main unique et protegee,
    # donc hors norme. Rien ne justifie de les ecarter de l audit.
    local -a segs; segs=(${(s:/:)repo})
    if (( ${#segs} > 2 )); then
        _ui_msg_fail "trop de niveaux : « $repo » (au plus <sous-groupe>/<repo>)"
        return 1
    fi
    # Chaque segment est un segment de chemin GitLab, pas une chaine libre. Le verifier
    # ferme d un coup les noms qui n ont pas de sens (« . », « ../x ») et ceux qui
    # fabriqueraient des cles dans un corps JSON — la construction par jq protege deja
    # ce dernier cas, mais un refus en amont vaut mieux qu un echappement en aval.
    # Forme volontairement sans `#` ni `(...)` : ces operateurs exigent EXTENDED_GLOB,
    # qui n est pas garanti — sous `zsh -f` ils sont litteraux et une premiere version
    # rejetait « cls-bff ».
    local seg
    for seg in $segs; do
        if [[ -z "$seg" || "$seg" == *[^A-Za-z0-9._-]* || "$seg" == .* ]]; then
            _ui_msg_fail "nom de repo invalide : « $repo » (attendu : lettres, chiffres, . _ -)"
            return 1
        fi
    done
    return 0
}

# --- Envs et norme derivee ---

# Normalise une liste d envs : espaces retires, doublons ecartes, ordre canonique
# retabli (dev < qlf < pprd < prd). L ordre de frappe n a donc aucune importance.
# Usage : _work_cfg_normalize_envs "prd,dev"  ->  "dev,prd"
# Return 1 si la liste est vide ou contient un env hors norme.
_work_cfg_normalize_envs() {
    local csv="${1:-}"
    local -a wanted out e
    wanted=(${(s:,:)csv})
    wanted=(${wanted//[[:space:]]/})
    wanted=(${wanted:#})

    (( ${#wanted} )) || { _ui_msg_fail "liste d envs vide"; return 1 }

    for e in $wanted; do
        if ! (( ${_WORK_CFG_ENVS_ALL[(Ie)$e]} )); then
            _ui_msg_fail "env inconnu : « $e » (attendu : ${_WORK_CFG_ENVS_ALL})"
            return 1
        fi
    done

    # On itere sur la norme, pas sur la saisie : l ordre canonique en decoule.
    for e in $_WORK_CFG_ENVS_ALL; do
        (( ${wanted[(Ie)$e]} )) && out+=($e)
    done

    print -r -- "${(j:,:)out}"
    return 0
}

# La branche par defaut attendue est la premiere env de la liste normalisee.
# Sur la norme complete c est dev ; sur --envs qlf,prd c est qlf.
_work_cfg_expected_default() {
    local -a envs
    envs=(${(s:,:)${1:-}})
    print -r -- "${envs[1]:-}"
}

# La protection se decide par NOM de branche, pas par rang dans la liste.
_work_cfg_env_is_protected() {
    (( ${_WORK_CFG_ENVS_PROTECTED[(Ie)${1:-}]} ))
}

# Contenu attendu du README d une branche d env : un titre H1, une ligne, rien d autre.
#
# Le nom du repo, pas son chemin : un repo de sous-groupe est designe « companion/api »
# dans toute la commande, mais son README porte « # api <branche> ». La spec dit « nom du
# repo », et c est ce que GitLab appelle le `path` du projet.
_work_cfg_readme_content() {
    print -r -- "# ${1##*/} ${2}"
}

# --- Planificateur ---

# Construit la liste des actions a partir d un etat, sans aucun appel reseau.
#
# Usage : _work_cfg_build_plan <repo> <envs_csv> <readme_optin> <default_branch> \
#                              <branches> <rules> <readmes>
#   branches : une branche par ligne
#   rules    : nom<TAB>push<TAB>merge<TAB>force
#   readmes  : branche<TAB>ok|absent|divergent
#
# Sortie : une action par ligne, champs separes par TAB. L ordre d emission est
# stable — les tests comparent des sorties entieres, et l ordre d application en
# depend (cf. _work_cfg_apply).
_work_cfg_build_plan() {
    local repo="$1" envs_csv="$2" readme_optin="$3" default_branch="$4"
    local branches_raw="$5" rules_raw="$6" readmes_raw="$7"

    local -a envs branches created
    envs=(${(s:,:)envs_csv})
    branches=(${(f)branches_raw})
    branches=(${branches:#})

    local -A rule_push rule_merge rule_force has_rule readme_state
    local line nom f2 f3 f4
    for line in ${(f)rules_raw}; do
        [[ -z "$line" ]] && continue
        IFS=$'\t' read -r nom f2 f3 f4 <<< "$line"
        has_rule[$nom]=1; rule_push[$nom]="$f2"; rule_merge[$nom]="$f3"; rule_force[$nom]="$f4"
    done
    for line in ${(f)readmes_raw}; do
        [[ -z "$line" ]] && continue
        IFS=$'\t' read -r nom f2 <<< "$line"
        readme_state[$nom]="$f2"
    done

    local expected_default e b
    expected_default=$(_work_cfg_expected_default "$envs_csv")
    local source_branch="${default_branch:-$expected_default}"

    # 1. branches d env manquantes, derivees du defaut courant
    for e in $envs; do
        if ! (( ${branches[(Ie)$e]} )); then
            print -r -- "branch_create	$e	$source_branch"
            created+=($e)
        fi
    done

    # 2. branche par defaut
    [[ "$default_branch" != "$expected_default" ]] && print -r -- "default_set	$expected_default"

    # 3-4. protections, par nom de branche
    for e in $envs; do
        if _work_cfg_env_is_protected "$e"; then
            if (( ! ${+has_rule[$e]} )); then
                print -r -- "protect_create	$e"
            elif [[ "$rule_push[$e]" != "$_WORK_CFG_PUSH_LEVEL" || \
                    "$rule_merge[$e]" != "$_WORK_CFG_MERGE_LEVEL" ]]; then
                # GitLab CE ne sait pas modifier un niveau d acces par PATCH :
                # DELETE puis POST, donc une breve fenetre de non-protection.
                print -r -- "protect_replace	$e"
            elif [[ "$rule_force[$e]" != false ]]; then
                print -r -- "protect_patch	$e"
            fi
        else
            (( ${+has_rule[$e]} )) && print -r -- "unprotect	$e"
        fi
    done

    # 5. regles orphelines. Une regle dont la branche va etre creee par ce plan
    #    n est PAS orpheline : elle deviendra une protection legitime.
    for nom in ${(ok)has_rule}; do
        (( ${branches[(Ie)$nom]} )) && continue
        (( ${created[(Ie)$nom]} )) && continue
        print -r -- "rule_delete_orphan	$nom"
    done

    # 6. README. D office sur ce que ce run vient de creer — la branche derive de
    #    dev et porte donc le README de dev, il n y a rien a ecraser. Sur une
    #    branche preexistante, un README ABSENT n ecrase rien non plus : il est
    #    ecrit sans --readme. Seul un contenu qui existe deja et DIVERGE reste
    #    opt-in — c est lui, et lui seul, que --readme protege de l ecrasement.
    #    Sans cette distinction, --fix seul ne peut jamais amener aux normes un
    #    depot depourvu de README, ce qui est le cas de tous les depots existants.
    for e in $envs; do
        if (( ${created[(Ie)$e]} )); then
            print -r -- "readme_write	$e"
        elif [[ "${readme_state[$e]:-ok}" == absent ]]; then
            print -r -- "readme_write	$e"
        elif [[ "${readme_state[$e]:-ok}" == divergent ]]; then
            if [[ "$readme_optin" == 1 ]]; then
                print -r -- "readme_write	$e"
            else
                print -r -- "ecart	README de $e ${readme_state[$e]} — relancer avec --readme"
            fi
        fi
    done

    # 7. branches hors norme. master/main sont candidates a la suppression ;
    #    tout le reste est conserve. demo-borne porte des config/* vivantes et
    #    demo-bff une feature/* : une regle « supprimer le hors-norme » les tuerait.
    for b in $branches; do
        (( ${envs[(Ie)$b]} )) && continue
        if [[ "$b" == master || "$b" == main ]]; then
            print -r -- "master_delete	$b"
        else
            print -r -- "warn	branche hors norme conservee : $b"
        fi
    done
}

# --- Couche reseau ---
#
# Calquee sur _work_es_curl / _work_es_json. Une difference assumee avec
# modules/gitlab/gitlab_logic.zsh : pas de -k. Verifie le 2026-08-07, la forge
# repond 200 sans desactiver la verification TLS — desactiver par precaution
# reviendrait a accepter n importe quel certificat pour rien.

_work_cfg_api() {
    print -r -- "https://${GITLAB_BASE_DOMAIN}/api/v4"
}

# Encode un chemin de projet ou de groupe pour l API (les / deviennent %2F).
_work_cfg_enc() {
    print -r -- "${1//\//%2F}"
}

_work_cfg_require() {
    if ! command -v curl &>/dev/null; then
        _ui_msg_fail "curl requis"; return 1
    fi
    if ! command -v jq &>/dev/null; then
        _ui_msg_fail "jq requis (brew install jq / apt install jq)"; return 1
    fi
    if [[ -z "${GITLAB_TOKEN:-}" && -f "$HOME/.gitlab_secrets" ]]; then
        source "$HOME/.gitlab_secrets"
    fi
    if [[ -z "${GITLAB_BASE_DOMAIN:-}" ]]; then
        _ui_msg_fail "GITLAB_BASE_DOMAIN non definie (voir ~/.gitlab_secrets)"; return 1
    fi
    if [[ -z "${GITLAB_TOKEN:-}" ]]; then
        _ui_msg_fail "GITLAB_TOKEN non defini (voir ~/.gitlab_secrets)"; return 1
    fi
    return 0
}

# Usage : _work_cfg_curl METHOD PATH [BODY]
# Sortie : 1re ligne = code HTTP, reste = corps. Return = code de sortie curl.
_work_cfg_curl() {
    local method=$1 api_path=$2 body="${3:-}"
    local -a opts
    opts=(-s --connect-timeout 5 --max-time 30 -X "$method")
    [[ -n "${SSL_CERT_FILE:-}" ]] && opts+=(--cacert "$SSL_CERT_FILE")
    opts+=(-H "PRIVATE-TOKEN: $GITLAB_TOKEN" -H 'Content-Type: application/json')
    [[ -n "$body" ]] && opts+=(-d "$body")

    local out ret
    out=$(command curl "${opts[@]}" -w $'\n%{http_code}' "$(_work_cfg_api)/$api_path" 2>/dev/null)
    ret=$?
    (( ret != 0 )) && return $ret
    print -r -- "${out##*$'\n'}"
    local resp="${out%$'\n'*}"
    [[ "$resp" != "$out" && -n "$resp" ]] && print -r -- "$resp"
    return 0
}

# Usage : _work_cfg_json METHOD PATH [BODY]
# Sortie : rien sur stdout. Return 1 en cas d echec, avec la cause dans
# _work_cfg_last_error — un « echec » nu ne dit pas si c est le VPN, le token
# ou le chemin qui est en cause, et les trois envoient a des endroits opposes.
#
# Le corps de la reponse va dans la globale _work_cfg_body, PAS sur stdout.
# Une substitution de commande $( ) est un sous-shell : un `typeset -g` qui y
# est pose est jete au retour, donc _work_cfg_last_error ne survivait jamais
# a un appel captant le corps (`x=$(_work_cfg_json ...)`). En sortant le corps
# par une globale, les deux appelants — celui qui veut le corps et celui qui
# ne veut que le code de retour — lisent la meme fonction sans sous-shell.
_work_cfg_json() {
    typeset -g _work_cfg_last_error="" _work_cfg_body=""
    local out code rc
    out=$(_work_cfg_curl "$@"); rc=$?
    if (( rc != 0 )); then
        case $rc in
            6)  _work_cfg_last_error="hote introuvable (DNS) — VPN actif ?" ;;
            7)  _work_cfg_last_error="connexion refusee" ;;
            28) _work_cfg_last_error="delai depasse" ;;
            35|60) _work_cfg_last_error="echec TLS — SSL_CERT_FILE pointe-t-il le bundle d entreprise ?" ;;
            *)  _work_cfg_last_error="curl a rendu $rc" ;;
        esac
        return 1
    fi
    code="${out%%$'\n'*}"
    if [[ "$code" != <-> ]]; then
        _work_cfg_last_error="reponse sans code HTTP — un proxy s est interpose ?"
        return 1
    fi
    if (( code >= 400 )); then
        case $code in
            401) _work_cfg_last_error="HTTP 401 — GITLAB_TOKEN refuse" ;;
            403) _work_cfg_last_error="HTTP 403 — droits insuffisants (Maintainer requis sur les branches protegees)" ;;
            404) _work_cfg_last_error="HTTP 404 — ressource introuvable" ;;
            *)   _work_cfg_last_error="HTTP $code" ;;
        esac
        # Le corps de la reponse peut refleter les en-tetes de la requete — un portail
        # d entreprise interpose le fait parfois, et ce module anticipe deja ce genre
        # d interposition. Le token n a rien a faire dans un message qu un appelant
        # affichera ou journalisera.
        if [[ "$out" == *$'\n'* ]]; then
            local _snippet; _snippet=$(print -r -- "${out#*$'\n'}" | head -c 300)
            [[ -n "${GITLAB_TOKEN:-}" ]] && _snippet="${_snippet//$GITLAB_TOKEN/<token masque>}"
            _work_cfg_last_error+=" : $_snippet"
        fi
        return 1
    fi
    [[ "$out" == *$'\n'* ]] && _work_cfg_body="${out#*$'\n'}"
    return 0
}

# --- Collecte de l etat distant ---

# Remplit les globales decrivant l etat du repo. Return 2 si le projet n existe pas.
_work_cfg_collect() {
    local bu="$1" app="$2" repo="$3" envs_csv="$4"
    typeset -g _work_cfg_pid="" _work_cfg_default="" \
               _work_cfg_branches="" _work_cfg_rules="" _work_cfg_readmes=""

    local full="$bu/applications/$app/configurations/$repo"
    local enc; enc=$(_work_cfg_enc "$full")

    local proj
    if ! _work_cfg_json GET "projects/$enc"; then
        [[ "$_work_cfg_last_error" == HTTP\ 404* ]] && return 2
        _ui_msg_fail "lecture du projet : $_work_cfg_last_error"
        return 1
    fi
    proj="$_work_cfg_body"
    _work_cfg_pid=$(print -r -- "$proj" | jq -r '.id')
    _work_cfg_default=$(print -r -- "$proj" | jq -r '.default_branch // ""')

    local br rules
    _work_cfg_json GET "projects/$_work_cfg_pid/repository/branches?per_page=100" || {
        _ui_msg_fail "lecture des branches : $_work_cfg_last_error"; return 1
    }
    br="$_work_cfg_body"
    _work_cfg_branches=$(print -r -- "$br" | jq -r '.[].name')

    _work_cfg_json GET "projects/$_work_cfg_pid/protected_branches?per_page=100" || {
        _ui_msg_fail "lecture des protections : $_work_cfg_last_error"; return 1
    }
    rules="$_work_cfg_body"
    _work_cfg_rules=$(print -r -- "$rules" | jq -r '
        .[] | [ .name,
                (.push_access_levels[0].access_level  // "0" | tostring),
                (.merge_access_levels[0].access_level // "0" | tostring),
                (.allow_force_push | tostring) ] | @tsv')

    # Etat des README, une lecture par branche d env existante.
    local -a envs; envs=(${(s:,:)envs_csv})
    local e want got code raw
    for e in $envs; do
        print -r -- "$_work_cfg_branches" | grep -qx -- "$e" || continue
        want=$(_work_cfg_readme_content "$repo" "$e")
        raw=$(_work_cfg_curl GET "projects/$_work_cfg_pid/repository/files/README%2Emd/raw?ref=$e")
        if (( $? != 0 )); then
            _ui_msg_fail "lecture du README de $e : appel reseau en echec"
            return 1
        fi
        code="${raw%%$'\n'*}"
        case "$code" in
            404) _work_cfg_readmes+="$e	absent"$'\n' ;;
            200)
                got="${raw#*$'\n'}"
                if [[ "${got%$'\n'}" == "$want" ]]; then
                    _work_cfg_readmes+="$e	ok"$'\n'
                else
                    _work_cfg_readmes+="$e	divergent"$'\n'
                fi ;;
            *)
                # Ne jamais traduire un echec reseau ou un refus en « divergent ».
                # Sous --fix --readme, un incident VPN ou un 403 ferait alors ecraser
                # un README qui n avait rien de divergent : un diagnostic errone
                # deviendrait une ecriture.
                _ui_msg_fail "lecture du README de $e : HTTP ${code:-<aucun code>}"
                return 1 ;;
        esac
    done
    return 0
}

# --- Volet local du plan ---

# Ajoute au plan ce qu il faut faire au clone local. Le planificateur reste pur : ces
# lignes viennent d ici, ou l I/O a deja droit de cite.
#
# Sans ce volet, une mise aux normes laisse le clone sur une branche que la commande
# vient de supprimer en amont — c est le cas de tous les depots mono-main d aujourd hui.
#
# Rien n est ajoute si l arbre local porte des modifications : basculer de branche les
# emporterait ailleurs, et ce n est pas a une commande de normalisation d en decider.
#
# Le troisieme argument, facultatif, porte les envs de la norme. Quand il est fourni, une
# branche courante qui EST un env de la norme n est pas deplacee : sans cette exception,
# `local_checkout` etait emis des que la branche differait du defaut, et un depot
# parfaitement conforme dont le clone etait sur `prd` — parce qu on y editait la config de
# production — etait rapporte non conforme, avec un code 2 et un plan d une action. Sous
# `--fix`, la branche etait quittee sans que rien ne l ait demande. Le besoin reel ne
# concerne que les branches que la norme ne garde pas : `main`, `master`, ou une branche
# qui n existe plus en face.
_work_cfg_local_plan() {
    local dest="$1" want="$2" envs_csv="${3:-}"
    [[ -d "$dest/.git" ]] || return 0

    if [[ -n "$(command git -C "$dest" status --porcelain 2>/dev/null)" ]]; then
        print -r -- "warn	clone local non synchronise : $dest porte des modifications"
        return 0
    fi

    local cur; cur=$(command git -C "$dest" branch --show-current 2>/dev/null)
    local -a norme; norme=(${(s:,:)envs_csv})
    # Un HEAD detache rend une chaine vide, qui n est dans aucune norme : la bascule est
    # alors proposee, et c est bien ce qu on veut.
    if [[ "$cur" != "$want" ]] && ! (( ${norme[(Ie)$cur]} )); then
        print -r -- "local_checkout	$want	$dest"
    fi

    # Les branches locales que la norme ne garde pas. `git branch -d` refusera celles
    # qui portent des commits non fusionnes : c est la garde, on ne la contourne pas.
    local b
    for b in ${(f)"$(command git -C "$dest" branch --format='%(refname:short)' 2>/dev/null)"}; do
        [[ "$b" == master || "$b" == main ]] || continue
        print -r -- "local_prune	$b	$dest"
    done
    return 0
}

# --- Rendu ---

# Compte les actions reelles d un plan : ni `warn` ni `ecart` n en sont.
_work_cfg_count_actions() {
    local line n=0
    for line in ${(f)${1:-}}; do
        [[ -z "$line" ]] && continue
        case "${line%%	*}" in warn|ecart) continue ;; esac
        (( n++ ))
    done
    print -r -- "$n"
}

# Compte les ecarts que ce run ne corrige pas. Ils ne produisent aucune action, mais
# ils interdisent d annoncer la conformite : un README absent EST un ecart au sens du
# controle 6 de la spec, seule sa CORRECTION est conditionnee a --readme. Sans cette
# distinction, un depot sans aucun README rendait 0 en affichant « conforme » juste
# sous la liste de ses propres ecarts.
_work_cfg_count_ecarts() {
    local line n=0
    for line in ${(f)${1:-}}; do
        [[ "${line%%	*}" == ecart ]] && (( n++ ))
    done
    print -r -- "$n"
}

# Rend un plan en texte lisible. Fonction pure : aucune lecture distante.
_work_cfg_render() {
    local repo="$1" plan="$2"
    local line kind a b n n_ec
    n=$(_work_cfg_count_actions "$plan")
    n_ec=$(_work_cfg_count_ecarts "$plan")

    if (( n == 0 )); then
        for line in ${(f)plan}; do
            [[ -z "$line" ]] && continue
            IFS=$'\t' read -r kind a b <<< "$line"
            case "$kind" in
                ecart) print -r -- "  ${_ui_yellow}!${_ui_nc} $a" ;;
                warn)  print -r -- "  ${_ui_yellow}!${_ui_nc} $a" ;;
            esac
        done
        if (( n_ec > 0 )); then
            print -r -- "  Aucune action applicable — $n_ec ecart(s) exigent --readme."
        else
            print -r -- "  Rien a faire — le repo est conforme."
        fi
        return 0
    fi

    print -r -- "${_ui_bold}Plan ($n actions)${_ui_nc}"
    for line in ${(f)plan}; do
        [[ -z "$line" ]] && continue
        IFS=$'\t' read -r kind a b <<< "$line"
        case "$kind" in
            branch_create) print -r -- "  + creer branche $a depuis $b" ;;
            default_set)   print -r -- "  ~ basculer la branche par defaut sur $a" ;;
            protect_create) print -r -- "  + proteger $a (Maintainers/Maintainers, force=off)" ;;
            protect_replace) print -r -- "  ~ remplacer la protection de $a — breve fenetre de non-protection (GitLab CE)" ;;
            protect_patch) print -r -- "  ~ desactiver allow_force_push sur $a" ;;
            unprotect)     print -r -- "  - deproteger $a" ;;
            rule_delete_orphan) print -r -- "  - supprimer la regle orpheline « $a »" ;;
            readme_write)  print -r -- "  ~ README de $a → « $(_work_cfg_readme_content "$repo" "$a") »" ;;
            master_delete) print -r -- "  - supprimer $a (sa protection sera retiree), sous reserve du merge-base" ;;
            local_checkout) print -r -- "  ~ clone local : fetch --prune puis basculer sur $a" ;;
            local_prune)   print -r -- "  - clone local : supprimer la branche $a (refuse si non fusionnee)" ;;
            ecart)         print -r -- "  ${_ui_yellow}!${_ui_nc} $a" ;;
            warn)          print -r -- "  ${_ui_yellow}!${_ui_nc} $a" ;;
        esac
    done
    return 0
}

# --- Point d entree ---

_work_cfg_usage() {
    print -r -- "Usage: work_config_repo [<repo>] [options]"
    print -r -- ""
    print -r -- "  Audite un repo de configuration, ou le met aux normes avec --fix."
    print -r -- "  Sans argument, la cible est deduite du repertoire courant."
    print -r -- ""
    print -r -- "  --bu <${(j:|:)_WORK_CFG_BU_ALL}>"
    print -r -- "  --app <nom>              application"
    print -r -- "  --envs <csv>             sous-ensemble d envs (defaut: ${(j:,:)_WORK_CFG_ENVS_ALL})"
    print -r -- "  --readme                 autorise la reecriture des README preexistants"
    print -r -- "  --fix                    applique ; sans lui, audit en lecture seule"
    print -r -- "  -h, --help               cette aide"
    print -r -- ""
    print -r -- "  Codes de sortie : 0 conforme ou corrige, 1 erreur, 2 ecarts detectes."
}

work_config_repo() {
    local bu="" app="" repo="" envs_csv="" readme_optin=0 do_fix=0 envs_given=0

    while (( $# )); do
        case "$1" in
            --bu)
                (( $# >= 2 )) || { _ui_msg_fail "--bu attend une valeur"; return 1 }
                bu="$2"; shift 2 ;;
            --app)
                (( $# >= 2 )) || { _ui_msg_fail "--app attend une valeur"; return 1 }
                app="$2"; shift 2 ;;
            --envs)
                (( $# >= 2 )) || { _ui_msg_fail "--envs attend une valeur"; return 1 }
                envs_csv="$2"; envs_given=1; shift 2 ;;
            --readme) readme_optin=1; shift ;;
            --fix)    do_fix=1; shift ;;
            -h|--help) _work_cfg_usage; return 0 ;;
            -*) _ui_msg_fail "option inconnue : $1"; _work_cfg_usage; return 1 ;;
            # « . » et « ./ » veulent dire « ici », pas « un repo nomme point ». C est
            # ce qu on tape spontanement, et le prendre au pied de la lettre construisait
            # une cible .../configurations/. sans que rien ne proteste.
            .|./) shift ;;
            *)  repo="$1"; shift ;;
        esac
    done

    # Deduction depuis le repertoire courant pour ce qui n a pas ete passe.
    if [[ -z "$bu" || -z "$app" || -z "$repo" ]]; then
        local parsed p_bu p_app p_repo
        if parsed=$(_work_cfg_parse_path "$PWD"); then
            IFS=$'\t' read -r p_bu p_app p_repo <<< "$parsed"
            [[ -z "$bu" ]]   && bu="$p_bu"
            [[ -z "$app" ]]  && app="$p_app"
            [[ -z "$repo" ]] && repo="$p_repo"
        fi
    fi

    _work_cfg_guard_target "$bu" "$app" "$repo" || return 1

    # Absence de --envs vaut la norme complete ; une valeur explicitement vide est une
    # erreur. ${x:-y} confondrait les deux et ferait passer `--envs ""` pour un defaut.
    (( envs_given )) || envs_csv="${(j:,:)_WORK_CFG_ENVS_ALL}"

    # _ui_msg_fail ecrit sur stdout (core/ui.zsh), donc capturer la sortie de
    # _work_cfg_normalize_envs avale aussi son message d erreur. On le reemet avant
    # de rendre la main : sans cela, `--envs uat` echoue sans rien dire.
    local _envs_norm
    _envs_norm=$(_work_cfg_normalize_envs "$envs_csv") || { print -r -- "$_envs_norm"; return 1 }
    envs_csv="$_envs_norm"

    _work_cfg_run "$bu" "$app" "$repo" "$envs_csv" "$readme_optin" "$do_fix"
}

# --- Orchestration ---

_work_cfg_run() {
    local bu="$1" app="$2" repo="$3" envs_csv="$4" readme_optin="$5" do_fix="$6"

    # master_delete lit cette globale pour connaitre sa cible de merge-base. La
    # renseigner ici, avant tout chemin qui pourrait mener a _work_cfg_apply,
    # garantit qu elle n est jamais vide au moment ou la garde en a besoin.
    typeset -g _work_cfg_envs_current="$envs_csv"

    _work_cfg_require || return 1

    _ui_header "Repo de configuration"
    _ui_section "Cible" "$bu/applications/$app/configurations/$repo"
    _ui_section "Envs" "$envs_csv"

    local rc; _work_cfg_collect "$bu" "$app" "$repo" "$envs_csv"; rc=$?
    (( rc == 1 )) && return 1
    if (( rc == 2 )); then
        _ui_msg_warn "le projet n existe pas encore sur la forge"
        (( do_fix )) || { _ui_msg_info "relancer avec --fix pour le creer"; return 2 }
        _work_cfg_create "$bu" "$app" "$repo" "$envs_csv"
        return $?
    fi

    local plan plan_local
    plan=$(_work_cfg_build_plan "$repo" "$envs_csv" "$readme_optin" "$_work_cfg_default" \
            "$_work_cfg_branches" "$_work_cfg_rules" "$_work_cfg_readmes")

    # Le clone local fait partie de la mise aux normes : sans lui, le depot reste sur
    # une branche que le plan vient de supprimer en amont.
    plan_local=$(_work_cfg_local_plan \
        "$(_work_cfg_local_path "$bu" "$app" "$repo")" \
        "$(_work_cfg_expected_default "$envs_csv")" \
        "$envs_csv")
    [[ -n "$plan_local" ]] && plan="${plan:+$plan$'\n'}$plan_local"

    echo ""
    _work_cfg_render "$repo" "$plan"

    # Un ecart sans action possible interdit le code 0 : la spec reserve 0 a
    # « conforme ou corrige ». Un depot dont tous les README manquent n est pas
    # conforme, meme si le corriger exige --readme.
    local n n_ec
    n=$(_work_cfg_count_actions "$plan")
    n_ec=$(_work_cfg_count_ecarts "$plan")
    (( n == 0 && n_ec == 0 )) && return 0
    (( n == 0 )) && return 2
    (( do_fix )) || return 2

    _work_cfg_confirm_and_apply "$repo" "$envs_csv" "$readme_optin" "$plan" \
        "$(_work_cfg_local_path "$bu" "$app" "$repo")"
}

# --- Dialogue de confirmation ---

# Lit la reponse au prompt. Tout ce qui n est pas y ou u vaut non — y compris
# une entree vide et un stdin ferme. Une execution non interactive ne doit jamais
# appliquer quoi que ce soit par defaut.
_work_cfg_read_answer() {
    local ans
    if ! read -r ans; then
        print -r -- "n"; return 0
    fi
    case "${(L)ans}" in
        y|yes|o|oui) print -r -- "y" ;;
        u|update)    print -r -- "u" ;;
        *)           print -r -- "n" ;;
    esac
}

# Boucle de confirmation. `u` recalcule le plan avec une nouvelle liste d envs et
# repropose : le sous-ensemble n est jamais persiste nulle part.
#
# Le cinquieme argument, facultatif, porte le chemin du clone local. Il sert au recalcul du
# volet local par `u` : ce chemin ne depend pas des envs, contrairement au defaut attendu,
# donc l appelant le calcule une fois et le passe.
_work_cfg_confirm_and_apply() {
    local repo="$1" envs_csv="$2" readme_optin="$3" plan="$4" local_dest="${5:-}"

    while true; do
        echo ""
        print -n -- "Appliquer ? [y/N/u] "
        local ans; ans=$(_work_cfg_read_answer)

        case "$ans" in
            y) _work_cfg_apply "$repo" "$plan"; return $? ;;
            n) _ui_msg_info "rien n a ete ecrit"; return 2 ;;
            u)
                print -n -- "Quels envs ? (${(j:,:)_WORK_CFG_ENVS_ALL}) "
                local raw; read -r raw || raw=""
                local new_envs=
                # _ui_msg_fail ecrit sur stdout, donc la capture avale la plainte.
                # Sans ce reemis, une saisie fautive fait juste reapparaitre le
                # prompt, muet : l utilisateur ne sait pas ce qu on lui reproche.
                new_envs=$(_work_cfg_normalize_envs "$raw") || { print -r -- "$new_envs"; continue }
                envs_csv="$new_envs"
                # Le sous-ensemble recalcule ici doit rester la cible vue par
                # master_delete : sans cette remise a jour, une restriction
                # d envs via `u` laisserait la garde viser l ancien defaut.
                typeset -g _work_cfg_envs_current="$envs_csv"
                _ui_section "Envs" "$envs_csv"
                plan=$(_work_cfg_build_plan "$repo" "$envs_csv" "$readme_optin" \
                        "$_work_cfg_default" "$_work_cfg_branches" "$_work_cfg_rules" \
                        "$_work_cfg_readmes")
                # Le volet local, RECALCULE et non recopie : la nouvelle liste d envs
                # change le defaut attendu, donc les anciennes lignes viseraient la
                # mauvaise branche. Sans ce bloc, `--fix` puis `u` normalisait le distant
                # et laissait le clone sur la branche qui venait d etre supprimee — le
                # defaut meme que ce volet existe pour corriger, atteint par le chemin
                # interactif.
                if [[ -n "$local_dest" ]]; then
                    local plan_local_u=
                    plan_local_u=$(_work_cfg_local_plan "$local_dest" \
                        "$(_work_cfg_expected_default "$envs_csv")" "$envs_csv")
                    [[ -n "$plan_local_u" ]] && plan="${plan:+$plan$'\n'}$plan_local_u"
                fi
                echo ""
                _work_cfg_render "$repo" "$plan"
                (( $(_work_cfg_count_actions "$plan") == 0 )) && \
                    { (( $(_work_cfg_count_ecarts "$plan") == 0 )) && return 0 || return 2 }
                ;;
        esac
    done
}

# --- Application ---

# Une branche n est supprimable que si son sommet est deja contenu dans la cible.
# Fonction pure, isolee pour etre testable : c est la seule garde entre un
# `master` reprenant des commits absents de `dev` et leur perte.
_work_cfg_sha_contained() {
    [[ -n "${1:-}" && -n "${2:-}" && "$1" == "$2" ]]
}

# Return 0 si <branche> est deja contenue dans <cible>.
# Return 1 si elle porte des commits absents de la cible.
# Return 2 si la question n a pas pu etre posee (reseau, droits, reponse inattendue).
#
# La distinction 1/2 n est pas cosmetique. Rendre 1 sur un VPN coupe reviendrait a
# annoncer « master porte des commits absents de dev » — factuellement faux — et a
# jeter le code HTTP que _work_cfg_last_error contient. C est la seule etape du plan
# qui decide d une suppression : elle doit dire quand elle ne sait pas.
_work_cfg_is_merged() {
    local pid="$1" src="$2" dst="$3" sha base
    local esrc edst
    esrc=$(_work_cfg_enc "$src"); edst=$(_work_cfg_enc "$dst")

    _work_cfg_json GET "projects/$pid/repository/branches/$esrc" || return 2
    sha=$(print -r -- "$_work_cfg_body" | jq -r '.commit.id // ""')
    # `|| return 2` sur le jq qui precede ne peut jamais se declencher : jq rend 0
    # grace au `// ""`, meme sur une reponse sans .commit.id. sha resterait vide et
    # la suite lirait ca comme des SHA differents — un return 1 (« porte des commits
    # absents ») quand la verite est « je n ai pas pu savoir ». Le test explicite
    # distingue les deux.
    [[ -n "$sha" && "$sha" != null ]] || return 2
    _work_cfg_json GET "projects/$pid/repository/merge_base?refs%5B%5D=$esrc&refs%5B%5D=$edst" || return 2
    base=$(print -r -- "$_work_cfg_body" | jq -r '.id // ""')
    [[ -n "$base" && "$base" != null ]] || return 2

    _work_cfg_sha_contained "$sha" "$base"
}

# Remet le plan dans l ordre d application. L API impose deux contraintes qui se
# croisent — on ne supprime pas la branche par defaut, on ne supprime pas une
# branche protegee — et les README doivent etre ecrits avant que les protections
# ne soient posees, sinon un repo neuf bute sur ses propres regles.
_work_cfg_sort_plan() {
    local -a order
    order=(branch_create default_set unprotect readme_write protect_create
           protect_replace protect_patch rule_delete_orphan master_delete
           local_checkout local_prune ecart warn)
    local kind line
    for kind in $order; do
        for line in ${(f)${1:-}}; do
            [[ -z "$line" ]] && continue
            [[ "${line%%	*}" == "$kind" ]] && print -r -- "$line"
        done
    done
}

# Execute le plan. S arrete a la premiere erreur : appliquer la suite d un plan
# dont une etape a echoue laisserait le repo dans un etat qu aucun des deux
# rapports ne decrit.
_work_cfg_apply() {
    local repo="$1" plan="$2"
    local pid="$_work_cfg_pid"
    local line kind a b ea
    local survivants=0

    # Les guillemets autour de la substitution ne sont pas decoratifs. Sans eux,
    # ${(f)$(...)} decoupe D ABORD sur IFS : tabulations et retours ligne deviennent
    # des espaces avant que (f) ne s applique. La boucle tourne alors une seule fois
    # sur le plan entier aplati, aucun case ne matche, et la fonction rend 0 sans
    # avoir rien applique — un « corrige » mensonger sur la seule etape qui ecrit.
    for line in ${(f)"$(_work_cfg_sort_plan "$plan")"}; do
        [[ -z "$line" ]] && continue
        IFS=$'\t' read -r kind a b <<< "$line"
        # Un nom de branche ou de regle peut porter un / — et une regle de protection
        # GitLab peut etre un joker (release/*). Non encode, il ajoute un segment de
        # chemin et la route ne s apparie plus.
        ea=$(_work_cfg_enc "$a")
        case "$kind" in
            branch_create)
                _work_cfg_json POST "projects/$pid/repository/branches?branch=$a&ref=$b" \
                    || { _ui_msg_fail "creation de $a : $_work_cfg_last_error"; return 1 }
                _ui_msg_ok "branche $a creee depuis $b" ;;
            default_set)
                # Corps construit par jq, comme les autres : $a est un nom de branche
                # normalise par ce module, mais rien ne justifie que ce corps reste le
                # seul construit par interpolation brute.
                local _body_defset=
                _body_defset=$(jq -n --arg br "$a" '{default_branch:$br}') \
                    || { _ui_msg_fail "construction du corps de bascule sur $a"; return 1 }
                _work_cfg_json PUT "projects/$pid" "$_body_defset" \
                    || { _ui_msg_fail "bascule du defaut sur $a : $_work_cfg_last_error"; return 1 }
                _ui_msg_ok "branche par defaut : $a" ;;
            unprotect)
                _work_cfg_json DELETE "projects/$pid/protected_branches/$ea" \
                    || { _ui_msg_fail "deprotection de $a : $_work_cfg_last_error"; return 1 }
                _ui_msg_ok "$a deprotegee" ;;
            readme_write)
                _work_cfg_write_readme "$pid" "$repo" "$a" || return 1 ;;
            protect_create)
                _work_cfg_protect "$pid" "$a" || return 1 ;;
            protect_replace)
                # L avertissement annonce une fenetre BREVE, pas une deprotection
                # definitive : si le POST qui suit echoue, il faut le dire aussi
                # explicitement que master_delete le dit plus bas, sinon $a reste
                # deprotegee en silence et l avertissement se lit comme une
                # reassurance fausse.
                _ui_msg_warn "$a : fenetre de non-protection le temps du remplacement"
                _work_cfg_json DELETE "projects/$pid/protected_branches/$ea" \
                    || { _ui_msg_fail "retrait de la protection de $a : $_work_cfg_last_error"; return 1 }
                _work_cfg_protect "$pid" "$a" || {
                    _ui_msg_fail "$a est restee DEPROTEGEE — la reproteger a la main"
                    return 1
                } ;;
            protect_patch)
                _work_cfg_json PATCH "projects/$pid/protected_branches/$ea" \
                    '{"allow_force_push":false}' \
                    || { _ui_msg_fail "allow_force_push sur $a : $_work_cfg_last_error"; return 1 }
                _ui_msg_ok "$a : allow_force_push desactive" ;;
            rule_delete_orphan)
                _work_cfg_json DELETE "projects/$pid/protected_branches/$ea" \
                    || { _ui_msg_fail "suppression de la regle « $a » : $_work_cfg_last_error"; return 1 }
                _ui_msg_ok "regle orpheline « $a » supprimee" ;;
            master_delete)
                local target merged deprotegee=0
                target=$(_work_cfg_expected_default "$_work_cfg_envs_current")
                _work_cfg_is_merged "$pid" "$a" "$target"; merged=$?

                if (( merged == 2 )); then
                    _ui_msg_fail "$a : merge-base inverifiable — $_work_cfg_last_error"
                    _ui_msg_info "aucune suppression tentee"
                    return 1
                fi
                if (( merged != 0 )); then
                    _ui_msg_warn "$a NON supprimee : elle porte des commits absents de $target"
                    survivants=1
                    continue
                fi

                # Retirer la protection fait partie de la suppression : l API refuse
                # de supprimer une branche protegee. On l annonce, au lieu de le faire
                # en silence — si la suppression echoue ensuite, master resterait
                # exposee et personne ne le saurait.
                if _work_cfg_json DELETE "projects/$pid/protected_branches/$ea"; then
                    deprotegee=1
                    _ui_msg_warn "$a : protection retiree pour permettre la suppression"
                fi
                if ! _work_cfg_json DELETE "projects/$pid/repository/branches/$ea"; then
                    _ui_msg_fail "suppression de $a : $_work_cfg_last_error"
                    (( deprotegee )) && _ui_msg_fail "$a est restee DEPROTEGEE — la reproteger a la main"
                    return 1
                fi
                _ui_msg_ok "$a supprimee (contenu repris dans $target)" ;;
            local_checkout)
                command git -C "$b" fetch --prune --quiet \
                    || { _ui_msg_fail "fetch dans $b"; return 1 }
                command git -C "$b" checkout --quiet "$a" \
                    || { _ui_msg_fail "bascule du clone local sur $a"; return 1 }
                _ui_msg_ok "clone local sur $a" ;;
            local_prune)
                # `-d` et non `-D` : git refuse une branche portant des commits non
                # fusionnes, et ce refus est la garde. On le rapporte au lieu de forcer.
                if command git -C "$b" branch -d "$a" >/dev/null 2>&1; then
                    _ui_msg_ok "branche locale $a supprimee"
                else
                    _ui_msg_warn "branche locale $a conservee : git la dit non fusionnee"
                fi ;;
            ecart|warn)
                _ui_msg_warn "$a" ;;
        esac
    done
    # Un ecart non corrige survit a l application, et une master conservee aussi.
    # Rendre 0 dirait « corrige » d un depot qui ne l est pas ; la spec reserve 0
    # a « conforme ou corrige ».
    (( survivants )) && return 2
    (( $(_work_cfg_count_ecarts "$plan") > 0 )) && return 2
    return 0
}

_work_cfg_protect() {
    local pid="$1" br="$2"
    _work_cfg_json POST "projects/$pid/protected_branches?name=$br&push_access_level=$_WORK_CFG_PUSH_LEVEL&merge_access_level=$_WORK_CFG_MERGE_LEVEL&allow_force_push=false" \
        || { _ui_msg_fail "protection de $br : $_work_cfg_last_error"; return 1 }
    _ui_msg_ok "$br protegee (Maintainers/Maintainers, force=off)"
    return 0
}

# Ecrit le README d une branche. Cree ou met a jour selon ce qui existe deja.
# Sur une branche protegee, le commit part sous l identite du token : Maintainer,
# il passe ; sinon GitLab rend 403 et on le dit. On ne deprotege jamais pour se
# faire de la place.
_work_cfg_write_readme() {
    local pid="$1" repo="$2" br="$3"
    local content; content=$(_work_cfg_readme_content "$repo" "$br")
    local action=create
    local probe; probe=$(_work_cfg_curl GET "projects/$pid/repository/files/README%2Emd?ref=$br")
    [[ "${probe%%$'\n'*}" == 200 ]] && action=update

    # Corps construit par jq, comme celui de la creation. $repo et $br viennent d une
    # saisie utilisateur que _work_cfg_guard_target ne valide que sur la non-vacuite :
    # interpoler l un ou l autre dans du JSON les laisse fabriquer des cles.
    local body
    body=$(jq -n --arg br "$br" --arg act "$action" --arg content "$content" \
                 --arg msg "chore: normalise le README ($repo $br)" \
        '{branch:$br, commit_message:$msg,
          actions:[{action:$act, file_path:"README.md", content:$content}]}') \
        || { _ui_msg_fail "construction du commit README de $br"; return 1 }

    _work_cfg_json POST "projects/$pid/repository/commits" "$body" \
        || { _ui_msg_fail "README de $br : $_work_cfg_last_error"; return 1 }
    _ui_msg_ok "README de $br normalise"
    return 0
}

# --- Creation ---

# Chemin canonique local, pur : aucun acces disque, aucun reseau.
# Usage : _work_cfg_local_path <bu> <app> <repo>
# Le groupe qui porte le projet. Un repo de premier niveau vit dans `configurations` ;
# un repo de sous-groupe (companion/api) vit dans `configurations/companion`. La
# distinction ne compte qu a la creation — la lecture passe par le chemin complet.
_work_cfg_repo_group() {
    local bu="$1" app="$2" repo="$3"
    local grp="$bu/applications/$app/configurations"
    [[ "$repo" == */* ]] && grp="$grp/${repo%/*}"
    print -r -- "$grp"
}

# Le nom du projet seul, sans son sous-groupe : GitLab n accepte pas de / dans un `path`.
_work_cfg_repo_leaf() {
    print -r -- "${1##*/}"
}

_work_cfg_local_path() {
    print -r -- "${WORK_DIR:-$HOME/work}/$1/applications/$2/configurations/$3"
}

# Cree le projet, ses branches, ses protections, puis le clone au chemin canonique.
# Le groupe `configurations` n est JAMAIS cree : une frappe fautive doit echouer,
# pas laisser un groupe orphelin sur la forge.
_work_cfg_create() {
    local bu="$1" app="$2" repo="$3" envs_csv="$4"
    local -a envs; envs=(${(s:,:)envs_csv})
    local grp leaf
    grp=$(_work_cfg_repo_group "$bu" "$app" "$repo")
    leaf=$(_work_cfg_repo_leaf "$repo")
    local enc; enc=$(_work_cfg_enc "$grp")

    # Ne PAS ecrire `_work_cfg_json ... | jq ... || { ... }` : le code de sortie d un
    # pipeline zsh est celui de sa DERNIERE commande, et PIPE_FAIL n est arme nulle
    # part dans ce projet. jq rend 0 sur une entree vide, donc la branche d erreur ne
    # partirait jamais et $_work_cfg_last_error serait perdu — un 404 ou un VPN coupe
    # passerait pour un groupe trouve mais sans identifiant.
    local gid raw_grp
    _work_cfg_json GET "groups/$enc" || {
        _ui_msg_fail "groupe $grp introuvable : $_work_cfg_last_error"
        _ui_msg_info "ce groupe n est pas cree automatiquement — le creer sur la forge d abord"
        return 1
    }
    raw_grp="$_work_cfg_body"
    gid=$(print -r -- "$raw_grp" | jq -r '.id // ""')
    [[ -n "$gid" ]] || { _ui_msg_fail "groupe $grp introuvable"; return 1 }

    local default_env="${envs[1]}"
    local dest; dest=$(_work_cfg_local_path "$bu" "$app" "$repo")

    # Le groupe existe : a partir d ici, le prochain appel ECRIT. La spec ouvre sa
    # section creation par « une fois le plan accepte » — jusqu ici rien ne le
    # demandait, donc un nom de repo mal tape sous --fix creait un projet, quatre
    # branches, deux regles, le clone, et deplacait le shell dans le clone, sans
    # qu aucun y explicite ait ete tape. Le plan affiche rend visible la cible
    # exacte (donc une paire --bu/cwd incoherente) avant que quoi que ce soit
    # n existe sur la forge.
    echo ""
    print -r -- "${_ui_bold}Plan de creation${_ui_nc}"
    # `$grp/$leaf` et non `$grp/$repo` : `$grp` descend deja dans le sous-groupe, et
    # `$repo` le porte encore. Les concatener affichait
    # « configurations/companion/companion/api » — un chemin qui n existe pas, sur le seul
    # ecran qui sert a reperer une cible erronee avant que quoi que ce soit ne soit cree.
    _ui_section "Chemin distant" "$grp/$leaf"
    _ui_section "Envs" "$envs_csv"
    _ui_section "Visibilite" "internal"
    _ui_section "Branche defaut" "$default_env"
    _ui_section "Chemin local" "$dest"
    echo ""
    print -n -- "Creer ? [y/N] "
    local ans; ans=$(_work_cfg_read_answer)
    if [[ "$ans" != y ]]; then
        _ui_msg_info "rien n a ete cree"
        return 2
    fi

    # Corps construit par jq, pas par interpolation. `_work_cfg_guard_target` ne
    # valide que la non-vacuite du nom : un repo contenant un guillemet injecterait
    # des cles arbitraires dans le seul appel qui cree de l etat distant. Le module
    # echappe deja correctement le contenu des README (jq -Rs) ; il n y a aucune
    # raison que la creation soit la seule exception.
    local body proj
    body=$(jq -n --arg name "$leaf" --arg path "$leaf" \
                 --argjson nsid "$gid" --arg def "$default_env" \
        '{name:$name, path:$path, namespace_id:$nsid, visibility:"internal",
          default_branch:$def, initialize_with_readme:true}') \
        || { _ui_msg_fail "construction du corps de creation"; return 1 }

    _work_cfg_json POST projects "$body" \
        || { _ui_msg_fail "creation du projet : $_work_cfg_last_error"; return 1 }
    proj="$_work_cfg_body"

    typeset -g _work_cfg_pid; _work_cfg_pid=$(print -r -- "$proj" | jq -r '.id')
    _ui_msg_ok "projet $grp/$leaf cree"

    # A partir d ici, le projet EXISTE sur la forge. Toute sortie en erreur doit le
    # dire : sinon l utilisateur lit « HTTP 403 » et ignore qu un projet a ete cree,
    # qu il est reparable, et que son clone local n arrivera jamais tout seul — le
    # clone ne vit que dans ce chemin de creation, jamais dans celui de l audit.
    local url
    url=$(print -r -- "$proj" | jq -r '.http_url_to_repo')

    _work_cfg_write_readme "$_work_cfg_pid" "$repo" "$default_env" \
        || { _work_cfg_create_partiel "$grp" "$repo" "$url" "$dest"; return 1 }

    local e
    for e in ${envs[2,-1]}; do
        _work_cfg_json POST "projects/$_work_cfg_pid/repository/branches?branch=$e&ref=$default_env" \
            || { _ui_msg_fail "creation de $e : $_work_cfg_last_error"
                 _work_cfg_create_partiel "$grp" "$repo" "$url" "$dest"; return 1 }
        _ui_msg_ok "branche $e creee depuis $default_env"
        _work_cfg_write_readme "$_work_cfg_pid" "$repo" "$e" \
            || { _work_cfg_create_partiel "$grp" "$repo" "$url" "$dest"; return 1 }
    done

    # Les protections viennent apres les README : l inverse ferait buter les commits
    # sur les regles qu on vient d ecrire.
    for e in $envs; do
        _work_cfg_env_is_protected "$e" || continue
        _work_cfg_protect "$_work_cfg_pid" "$e" \
            || { _work_cfg_create_partiel "$grp" "$repo" "$url" "$dest"; return 1 }
    done

    mkdir -p "${dest:h}" \
        || { _ui_msg_fail "creation de ${dest:h}"
             _work_cfg_create_partiel "$grp" "$repo" "$url" "$dest"; return 1 }

    # Meme mecanique d authentification que scripts/clone-projects.sh : un `git clone`
    # nu sur une URL interne invite un prompt (ou echoue net en non-interactif), au
    # milieu d une sequence qui a deja cree du projet, des branches et des regles
    # sur la forge.
    if ! git -c "http.extraheader=PRIVATE-TOKEN: $GITLAB_TOKEN" clone "$url" "$dest"; then
        _ui_msg_fail "clone en echec"
        _work_cfg_create_partiel "$grp" "$repo" "$url" "$dest"
        _ui_msg_info "si $dest existe deja et n est pas vide, le vider ou cloner ailleurs"
        return 1
    fi
    _ui_msg_ok "clone : $dest"

    # Un cd qui echoue ne doit pas passer pour un succes silencieux : l utilisateur
    # a lu « clone : ... » et se croirait dans le depot.
    cd "$dest" || _ui_msg_warn "clone fait, mais cd impossible vers $dest"
    return 0
}

# Nomme l etat distant quand la sequence de creation s arrete en chemin, et la
# facon d en sortir. Les deux sont necessaires : la reprise par --fix repare le
# distant, mais elle ne clonera jamais — le clone n existe que dans la creation.
_work_cfg_create_partiel() {
    local grp="$1" repo="$2" url="$3" dest="$4"
    # Meme raison qu au plan de creation : `$grp` descend deja dans le sous-groupe. Ce
    # helper recoit `grp` et `repo`, pas la feuille, donc il la derive lui-meme — le
    # chemin qu il imprime sert a retrouver le projet sur la forge, et un chemin double
    # n y menerait pas.
    local leaf; leaf=$(_work_cfg_repo_leaf "$repo")
    # Volontairement neutre sur l etat d avancement : ce helper sert aussi bien apres
    # un echec distant qu apres un echec de mkdir ou de clone, ou le distant est
    # complet. Annoncer « incomplet » serait faux dans la moitie des cas.
    _ui_msg_info "le projet $grp/$leaf existe desormais sur la forge"
    _ui_msg_info "verifier ou terminer la mise aux normes : work_config_repo --fix $repo"
    _ui_msg_info "recuperer le clone local   : git -c \"http.extraheader=PRIVATE-TOKEN: \$GITLAB_TOKEN\" clone $url $dest"
}
