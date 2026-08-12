# ==============================================================================
# Work Merch — interrogation de l API produits merch
# ==============================================================================
# Un produit se cherche par l un de quatre identifiants : EAN, offre, SAP ou PIM.
# L API en prend un seul a la fois, et le nom long de chaque option EST le nom du
# parametre de requete — il n y a donc aucune table de correspondance a maintenir, et
# `--offerId` garde son camelCase pour cette raison.

# --- Configuration (env.d/work.zsh ou ~/.secrets, jamais versionnee) ---
#
# Aucune valeur par defaut, delibere : ce depot est public, et un nom d hote d entreprise
# en dur y est de la nomenclature d infrastructure offerte a qui lit le code. C est la meme
# regle que pour ZANVIL_WORK_ES_URL, et `tests/bin/internal-hostnames` la fait respecter.
# Sans reglage, les commandes refusent au lieu d interroger une instance qui n est pas la
# leur — le bon sens du refus : un poste non configure ne doit pas deviner.

_work_merch_host() {
    case "${1:-prod}" in
        prod) echo "${ZANVIL_WORK_MERCH_HOST_PROD:-}" ;;
        qlf)  echo "${ZANVIL_WORK_MERCH_HOST_QLF:-}"  ;;
    esac
}

# Une cle par environnement, sans repli de l une sur l autre. Un repli silencieux
# enverrait la cle de production a la qualification le jour ou celle de qlf manque : le
# refus dit ou est le trou, le repli le cache.
_work_merch_api_key() {
    case "${1:-prod}" in
        prod) echo "${ZANVIL_WORK_MERCH_API_KEY_PROD:-}" ;;
        qlf)  echo "${ZANVIL_WORK_MERCH_API_KEY_QLF:-}"  ;;
    esac
}

# L organisation garde un defaut, contrairement aux hotes : c est un code metier, pas une
# adresse, et il ne mene nulle part seul. Meme statut que ZANVIL_WORK_ES_INDEX.
_work_merch_org() {
    echo "${ZANVIL_WORK_MERCH_ORG:-OCFR}"
}

_WORK_MERCH_PATH_TMPL='offer/merch-v3/organizations/%s/products'

# --- Garde commune : outils et configuration avant tout appel reseau ---

_work_merch_require() {
    local env=$1
    if ! command -v curl &>/dev/null; then
        _ui_msg_fail "curl requis"
        return 1
    fi
    if [[ -z "$(_work_merch_host "$env")" ]]; then
        _ui_msg_fail "ZANVIL_WORK_MERCH_HOST_${env:u} non definie (voir examples/env.d/work.zsh)"
        return 1
    fi
    if [[ -z "$(_work_merch_api_key "$env")" ]]; then
        _ui_msg_fail "ZANVIL_WORK_MERCH_API_KEY_${env:u} non definie"
        _ui_msg_info "la cle va dans ~/.secrets ou env.d/work.zsh — jamais dans un fichier versionne"
        return 1
    fi
    return 0
}

# --- Appel ---

# Usage : _work_merch_curl <env> <param> <valeur>
# Sortie : 1ere ligne = code HTTP, reste = corps.
# Return : code de sortie curl (0 = reponse recue, meme en erreur HTTP).
_work_merch_curl() {
    local env=$1 param=$2 value=$3
    local host org url
    host="$(_work_merch_host "$env")"
    org="$(_work_merch_org)"
    url="https://${host}/$(printf "$_WORK_MERCH_PATH_TMPL" "$org")"

    local -a opts
    opts=(-s --connect-timeout 5 --max-time 30)
    # Le host de qualification vit derriere la PKI d entreprise : sans ce cacert, la
    # negociation TLS echoue avec un code 60 qui ressemble a une panne reseau.
    [[ -n "${SSL_CERT_FILE:-}" ]] && opts+=(--cacert "$SSL_CERT_FILE")
    opts+=(-H 'Accept-Language: fr_FR')
    # `--get --data-urlencode` plutot qu une query concatenee : la valeur est encodee par
    # curl, donc un identifiant contenant & ou = ne peut pas fabriquer un second parametre.
    opts+=(--get --data-urlencode "${param}=${value}")
    opts+=(-w $'\n%{http_code}')

    # La cle passe par un fichier de configuration lu sur stdin, pas par argv : un `-H` en
    # ligne de commande est lisible dans `ps` par tout processus du meme utilisateur.
    # `_work_es_curl` met ES_PASSWORD en argv ; c est une dette, pas un modele a copier.
    local out
    out=$(printf 'header = "x-api-key: %s"\n' "$(_work_merch_api_key "$env")" \
        | command curl "${opts[@]}" --config - "$url" 2>/dev/null)
    local ret=$?
    (( ret != 0 )) && return $ret

    print -r -- "${out##*$'\n'}"
    local body="${out%$'\n'*}"
    [[ "$body" != "$out" && -n "$body" ]] && print -r -- "$body"
    return 0
}

# --- Aide ---

_work_merch_usage() {
    cat <<'EOF'
Usage : work_merch_product <critere> [--prod|--qlf]
        get_merch_product  <critere> [--prod|--qlf]

Critere (exactement un) :
  -e, --ean <ean>          Code EAN
  -o, --offerId <id>       Identifiant d offre
  -s, --sapId <id>         Identifiant SAP
  -p, --pimId <id>         Identifiant PIM

Environnement :
  --prod                   Production (defaut)
  --qlf                    Qualification
  -h, --help               Cette aide

Sortie : indentee par jq sur un terminal, JSON brut dans un pipe ou un fichier.

Configuration (env.d/work.zsh ou ~/.secrets, jamais versionnee) :
  ZANVIL_WORK_MERCH_HOST_PROD / _HOST_QLF
  ZANVIL_WORK_MERCH_API_KEY_PROD / _API_KEY_QLF
  ZANVIL_WORK_MERCH_ORG        (defaut OCFR)

Exemples :
  work_merch_product -e 3660000000000
  work_merch_product --offerId 12345 --qlf
  work_merch_product -s 987654 | jq '.products[0].label'
EOF
}

# --- Fonction publique ---

work_merch_product() {
    local env=prod param="" value="" crit_opt=""

    while (( $# )); do
        case "$1" in
            -e|--ean|-o|--offerId|-s|--sapId|-p|--pimId)
                local p
                case "$1" in
                    -e|--ean)     p=ean     ;;
                    -o|--offerId) p=offerId ;;
                    -s|--sapId)   p=sapId   ;;
                    -p|--pimId)   p=pimId   ;;
                esac
                # Deux criteres dans la meme ligne de commande ne sont pas une preference a
                # arbitrer : l API n en prend qu un, et deviner lequel produirait une
                # reponse qui ne repond pas a la question posee.
                if [[ -n "$param" ]]; then
                    _ui_msg_fail "deux criteres a la fois : --$param et --$p"
                    _ui_msg_info "l API n en accepte qu un — n en garder qu un"
                    return 1
                fi
                if [[ -z "${2:-}" || "${2}" == -* ]]; then
                    _ui_msg_fail "valeur manquante apres $1"
                    return 1
                fi
                param=$p; value=$2; crit_opt=$1
                # `shift 2` non garde boucle a l infini quand le flag est le dernier
                # argument — piege zsh releve en review sur work_es_count.
                if (( $# >= 2 )); then shift 2; else shift; fi
                ;;
            --prod) env=prod; shift ;;
            --qlf)  env=qlf;  shift ;;
            -h|--help) _work_merch_usage; return 0 ;;
            *)
                _ui_msg_fail "option inconnue : $1"
                _ui_msg_info "work_merch_product --help"
                return 1
                ;;
        esac
    done

    if [[ -z "$param" ]]; then
        _ui_msg_fail "aucun critere — passer -e, -o, -s ou -p"
        echo ""
        _work_merch_usage
        return 1
    fi

    _work_merch_require "$env" || return 1

    local out code curl_rc
    out=$(_work_merch_curl "$env" "$param" "$value")
    curl_rc=$?
    if (( curl_rc != 0 )); then
        # Les codes qu on rencontre vraiment ici. Le reste est rendu tel quel : inventer
        # une phrase pour chacun des quatre-vingts vaudrait moins que le numero, qui se
        # cherche. Meme raisonnement que _work_es_json.
        local why
        case $curl_rc in
            6)  why="hote introuvable (DNS) — VPN actif ?" ;;
            7)  why="connexion refusee — instance joignable ?" ;;
            28) why="delai depasse" ;;
            35|60) why="echec TLS — certificat d entreprise installe ? (SSL_CERT_FILE)" ;;
            *)  why="curl a rendu $curl_rc" ;;
        esac
        _ui_msg_fail "appel merch en echec ($env) : $why"
        return 1
    fi

    code="${out%%$'\n'*}"
    if [[ "$code" != <-> ]]; then
        _ui_msg_fail "reponse sans code HTTP — un proxy s est interpose ?"
        return 1
    fi

    local body=""
    [[ "$out" == *$'\n'* ]] && body="${out#*$'\n'}"

    if (( code >= 400 )); then
        case $code in
            401|403) _ui_msg_fail "HTTP $code — ZANVIL_WORK_MERCH_API_KEY_${env:u} refusee" ;;
            404) _ui_msg_fail "HTTP 404 — aucun produit pour $crit_opt $value" ;;
            *)   _ui_msg_fail "HTTP $code" ;;
        esac
        # Le corps d une erreur porte souvent le motif exact ; le taire obligerait a
        # rejouer la requete a la main pour le lire.
        [[ -n "$body" ]] && print -r -- "$body" >&2
        return 1
    fi

    # jq sur un terminal, brut ailleurs : le pipe en dur empecherait de rediriger vers un
    # fichier ou de rejouer avec un autre filtre.
    if [[ -t 1 ]] && command -v jq &>/dev/null; then
        print -r -- "$body" | jq
    else
        print -r -- "$body"
    fi
    return 0
}

# Le nom court demande. C est une fonction et non un alias, et le lazy loader l impose :
# `.lazy` remplace chaque nom publie par un stub qui source le module puis appelle
# `"$func"`. Or l expansion d alias n a pas lieu sur un mot issu d une variable — un alias
# ne serait donc jamais atteint avant le premier appel, et l inscrire dans `.lazy` ferait
# du stub un appel a lui-meme, en boucle. Une vraie fonction, redefinie par le source,
# ferme les deux cas.
get_merch_product() {
    work_merch_product "$@"
}

# --- Volet de work_status ---

_work_merch_status_section() {
    echo ""
    echo -e "${_ui_bold}Merch${_ui_nc}"
    _ui_separator 44
    local env
    for env in prod qlf; do
        local h k
        h="$(_work_merch_host "$env")"
        k="$(_work_merch_api_key "$env")"
        if [[ -n "$h" && -n "$k" ]]; then
            _ui_section "${env:u}" "${_ui_green}configure${_ui_nc}"
        elif [[ -n "$h" || -n "$k" ]]; then
            _ui_section "${env:u}" "${_ui_yellow}incomplet ($([[ -z "$h" ]] && echo 'hote' || echo 'cle') manquant)${_ui_nc}"
        else
            _ui_section "${env:u}" "${_ui_dim}non configure${_ui_nc}"
        fi
    done
    _ui_section "Organisation" "$(_work_merch_org)"
}
