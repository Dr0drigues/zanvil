#!/usr/bin/env bash
# Verifie work_config_repo : chemin canonique, refus durs, normalisation des envs,
# et le planificateur pur. Aucun appel reseau.
# Usage : scripts/tests/work-config-repos.test.sh
#
# Les cas sont synthetiques : zanvil est public, aucune nomenclature interne reelle
# n a sa place ici.
set -uo pipefail

ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"
MOD="$ROOT/modules/work/config_repos.zsh"

TEST_TMPDIR=$(mktemp -d) || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TEST_TMPDIR"' EXIT
echo 0 > "$TEST_TMPDIR/pass"
echo 0 > "$TEST_TMPDIR/fail"

assert_equals() {
    local label="$1" needle="$2" out
    out=$(cat)
    if [[ "$out" == "$needle" ]]; then
        printf '  ok   %s\n' "$label"
        echo $(($(cat "$TEST_TMPDIR/pass") + 1)) > "$TEST_TMPDIR/pass"
    else
        printf '  FAIL %s\n       attendu : %s\n       obtenu  : %s\n' \
            "$label" "$needle" "$out"
        echo $(($(cat "$TEST_TMPDIR/fail") + 1)) > "$TEST_TMPDIR/fail"
    fi
}

# Lance une expression zsh avec ui.zsh et le module charges, WORK_DIR maitrise.
zc() {
    zsh -f -c "
        WORK_DIR='$TEST_TMPDIR/work'
        source '$ROOT/core/ui.zsh' >/dev/null 2>&1
        source '$MOD'
        $1
    " 2>&1
}

echo "== chemin canonique =="

zc '_work_cfg_parse_path "$WORK_DIR/blg/applications/demoapp/configurations/demo-front"' \
    | assert_equals "chemin canonique decompose" "$(printf 'blg\tdemoapp\tdemo-front')"

zc '_work_cfg_parse_path "$WORK_DIR/blg/application/demoapp/configurations/demo-front" || print refuse' \
    | assert_equals "application au singulier refuse" "refuse"

zc '_work_cfg_parse_path "$WORK_DIR/xxx/applications/demoapp/configurations/demo-front" || print refuse' \
    | assert_equals "BU inconnue refusee" "refuse"

zc '_work_cfg_parse_path "$WORK_DIR/blg/applications/demoapp/components/demo-front" || print refuse' \
    | assert_equals "hors groupe configurations refuse" "refuse"

# Un chemin companion est RECONNU, pas rejete par l arite. Le rejeter ici renverrait
# « BU inconnue » a quelqu un dont la BU est valide : le message nommerait le mauvais
# probleme. C est _work_cfg_guard_target qui refuse, et qui sait dire pourquoi.
zc '_work_cfg_parse_path "$WORK_DIR/blg/applications/demoapp/configurations/companion/app"' \
    | assert_equals "chemin companion reconnu, pas rejete par l arite" "$(printf 'blg\tdemoapp\tcompanion/app')"

zc '_work_cfg_guard_target blg demoapp companion/app 2>&1 | grep -o "companion est hors perimetre"' \
    | assert_equals "le garde nomme le sous-groupe companion" "companion est hors perimetre"

zc '_work_cfg_parse_path "$WORK_DIR/blg/applications/demoapp/configurations/pasompanion/app" || print refuse' \
    | assert_equals "six segments hors companion : toujours refuse" "refuse"

zc '_work_cfg_parse_path "/ailleurs/blg/applications/demoapp/configurations/demo-front" || print refuse' \
    | assert_equals "hors WORK_DIR refuse" "refuse"

echo
echo "== refus durs, sans reseau =="

zc '_work_cfg_guard_target blg demoapp demo-front && print ok' \
    | assert_equals "cible legitime acceptee" "ok"

zc '_work_cfg_guard_target blg demoapp technical-assets >/dev/null 2>&1 || print refuse' \
    | assert_equals "technical-assets refuse" "refuse"

zc '_work_cfg_guard_target blg demoapp companion >/dev/null 2>&1 || print refuse' \
    | assert_equals "companion refuse" "refuse"

zc '_work_cfg_guard_target xxx demoapp demo-front >/dev/null 2>&1 || print refuse' \
    | assert_equals "BU inconnue refusee au garde" "refuse"

zc '_work_cfg_guard_target blg "" demo-front >/dev/null 2>&1 || print refuse' \
    | assert_equals "app vide refusee" "refuse"

zc '_work_cfg_guard_target blg demoapp "" >/dev/null 2>&1 || print refuse' \
    | assert_equals "repo vide refuse" "refuse"

echo
echo "== un nom de repo est un segment de chemin, pas une chaine libre =="

zc '_work_cfg_guard_target blg demoapp "../x" >/dev/null 2>&1 || print refuse' \
    | assert_equals "un nom avec une barre est refuse" "refuse"

zc '_work_cfg_guard_target blg demoapp "a b" >/dev/null 2>&1 || print refuse' \
    | assert_equals "un nom avec une espace est refuse" "refuse"

# Ferme en amont ce que la construction jq echappe en aval : mieux vaut refuser
# un nom porteur de guillemets que de compter sur l echappement seul.
zc '_work_cfg_guard_target blg demoapp '"'"'x","visibility":"public'"'"' >/dev/null 2>&1 || print refuse' \
    | assert_equals "un nom porteur de guillemets est refuse" "refuse"

# Le motif ne doit pas dependre d EXTENDED_GLOB : sous zsh -f les operateurs # et (...)
# sont litteraux, et une forme qui en depend rejetait « cls-bff ».
zc '_work_cfg_guard_target blg demoapp demo-front && print ok' \
    | assert_equals "un nom legitime avec tiret passe" "ok"

zc '_work_cfg_guard_target blg demoapp demo_front.v2 && print ok' \
    | assert_equals "un nom legitime avec _ et . passe" "ok"

# « . » veut dire « ici ». Le prendre au pied de la lettre construisait une cible
# .../configurations/. sans que rien ne proteste.
zc 'd="$WORK_DIR/blg/applications/demoapp/configurations/demo-front"
    mkdir -p "$d"; cd "$d"
    GITLAB_BASE_DOMAIN=127.0.0.1:9 GITLAB_TOKEN=x
    work_config_repo . 2>&1 | grep -o "configurations/demo-front"' \
    | assert_equals "« . » vaut ici, pas un repo nomme point" "configurations/demo-front"

# Le refus doit tomber AVANT tout appel reseau. Un curl factice depose un marqueur :
# comparer la sortie ne suffirait pas, _ui_msg_fail ecrit sur stdout (core/ui.zsh:202)
# comme tout le projet, donc son message se melerait a ce qu on mesure.
# Limite assumee : un `command curl` contournerait ce stub. La garde vaut pour les
# appels passant par le nom, ce qui suffit a detecter une regression de structure.
zc 'marker="${TMPDIR:-/tmp}/work-cfg-curl-called.$$"
    rm -f "$marker"
    curl() { print called >> "$marker" }
    _work_cfg_guard_target blg demoapp technical-assets >/dev/null 2>&1
    rc=$?
    if [[ -f "$marker" ]]; then reseau=oui; else reseau=non; fi
    rm -f "$marker"
    print "rc=$rc reseau=$reseau"' \
    | assert_equals "technical-assets refuse sans toucher au reseau" "rc=1 reseau=non"

echo
echo "== normalisation des envs =="

zc '_work_cfg_normalize_envs "prd,dev"' \
    | assert_equals "ordre canonique retabli" "dev,prd"

zc '_work_cfg_normalize_envs "dev,dev,qlf"' \
    | assert_equals "doublons ecartes" "dev,qlf"

zc '_work_cfg_normalize_envs ""  >/dev/null 2>&1 || print refuse' \
    | assert_equals "liste vide refusee" "refuse"

zc '_work_cfg_normalize_envs "dev,uat" >/dev/null 2>&1 || print refuse' \
    | assert_equals "env inconnu refuse" "refuse"

zc '_work_cfg_normalize_envs "dev, qlf "' \
    | assert_equals "espaces autour des valeurs tolerees" "dev,qlf"

echo
echo "== norme derivee =="

zc '_work_cfg_expected_default "dev,qlf,pprd,prd"' \
    | assert_equals "defaut attendu sur la norme complete" "dev"

zc '_work_cfg_expected_default "qlf,prd"' \
    | assert_equals "defaut attendu sans dev" "qlf"

zc '_work_cfg_env_is_protected prd && print oui || print non' \
    | assert_equals "prd protegee" "oui"

zc '_work_cfg_env_is_protected pprd && print oui || print non' \
    | assert_equals "pprd protegee" "oui"

zc '_work_cfg_env_is_protected dev && print oui || print non' \
    | assert_equals "dev non protegee" "non"

zc '_work_cfg_env_is_protected qlf && print oui || print non' \
    | assert_equals "qlf non protegee" "non"

echo
echo "== contenu README =="

zc '_work_cfg_readme_content demo-front dev' \
    | assert_equals "README en H1, une ligne" "# demo-front dev"

zc '_work_cfg_readme_content demo-front prd | wc -l | tr -d " "' \
    | assert_equals "README fait exactement une ligne" "1"

echo
echo "== planificateur : repo conforme =="

# demo-front conforme : 4 branches, defaut dev, pprd et prd protegees 40/40/false.
zc 'br=$(print -l dev qlf pprd prd)
    rules=$(printf "pprd\t40\t40\tfalse\nprd\t40\t40\tfalse")
    rm=$(printf "dev\tok\nqlf\tok\npprd\tok\nprd\tok")
    _work_cfg_build_plan demo-front dev,qlf,pprd,prd 0 dev "$br" "$rules" "$rm" | wc -l | tr -d " "' \
    | assert_equals "repo conforme : aucune action" "0"

echo
echo "== planificateur : deux branches d env absentes =="

# demo-docs : dev (defaut) et prd existent ; regles pprd et prd deja conformes.
zc 'br=$(print -l dev prd)
    rules=$(printf "pprd\t40\t40\tfalse\nprd\t40\t40\tfalse")
    rm=$(printf "dev\tok\nprd\tok")
    _work_cfg_build_plan demo-docs dev,qlf,pprd,prd 0 dev "$br" "$rules" "$rm"' \
    | assert_equals "norme complete : creations + README d office" \
"$(printf 'branch_create\tqlf\tdev\nbranch_create\tpprd\tdev\nreadme_write\tqlf\nreadme_write\tpprd')"

# La regle pprd n est PAS orpheline quand le plan cree la branche pprd.
zc 'br=$(print -l dev prd)
    rules=$(printf "pprd\t40\t40\tfalse\nprd\t40\t40\tfalse")
    rm=$(printf "dev\tok\nprd\tok")
    _work_cfg_build_plan demo-docs dev,qlf,pprd,prd 0 dev "$br" "$rules" "$rm" \
      | grep -c rule_delete_orphan' \
    | assert_equals "regle dont la branche va etre creee : pas orpheline" "0"

# Restreindre a dev,qlf rend la regle pprd orpheline et sort prd du perimetre.
zc 'br=$(print -l dev prd)
    rules=$(printf "pprd\t40\t40\tfalse\nprd\t40\t40\tfalse")
    rm=$(printf "dev\tok\nprd\tok")
    _work_cfg_build_plan demo-docs dev,qlf 0 dev "$br" "$rules" "$rm"' \
    | assert_equals "envs restreints : orpheline detectee, prd conservee" \
"$(printf 'branch_create\tqlf\tdev\nrule_delete_orphan\tpprd\nreadme_write\tqlf\nwarn\tbranche hors norme conservee : prd')"

echo
echo "== planificateur : protections =="

zc 'br=$(print -l dev prd); rm=$(printf "dev\tok\nprd\tok")
    _work_cfg_build_plan demo-x dev,prd 0 dev "$br" "" "$rm"' \
    | assert_equals "regle absente sur prd : creation" "$(printf 'protect_create\tprd')"

zc 'br=$(print -l dev prd); rm=$(printf "dev\tok\nprd\tok")
    rules=$(printf "prd\t30\t40\tfalse")
    _work_cfg_build_plan demo-x dev,prd 0 dev "$br" "$rules" "$rm"' \
    | assert_equals "niveau d acces divergent : remplacement" "$(printf 'protect_replace\tprd')"

zc 'br=$(print -l dev prd); rm=$(printf "dev\tok\nprd\tok")
    rules=$(printf "prd\t40\t40\ttrue")
    _work_cfg_build_plan demo-x dev,prd 0 dev "$br" "$rules" "$rm"' \
    | assert_equals "seul allow_force_push divergent : patch" "$(printf 'protect_patch\tprd')"

zc 'br=$(print -l dev qlf); rm=$(printf "dev\tok\nqlf\tok")
    rules=$(printf "qlf\t40\t40\tfalse")
    _work_cfg_build_plan demo-x dev,qlf 0 dev "$br" "$rules" "$rm"' \
    | assert_equals "qlf protegee a tort : deprotection" "$(printf 'unprotect\tqlf')"

echo
echo "== planificateur : README opt-in =="

zc 'rm=$(printf "dev\tdivergent")
    _work_cfg_build_plan demo-x dev 0 dev "dev" "" "$rm"' \
    | assert_equals "README preexistant divergent sans --readme : averti, pas ecrit" \
"$(printf 'ecart\tREADME de dev divergent — relancer avec --readme')"

zc 'rm=$(printf "dev\tdivergent")
    _work_cfg_build_plan demo-x dev 1 dev "dev" "" "$rm"' \
    | assert_equals "README preexistant divergent avec --readme : ecrit" \
"$(printf 'readme_write\tdev')"

zc 'rm=$(printf "dev\tok")
    _work_cfg_build_plan demo-x dev,qlf 0 dev "dev" "" "$rm" | grep readme_write' \
    | assert_equals "branche creee dans le run : README ecrit sans --readme" \
"$(printf 'readme_write\tqlf')"

# Un README ABSENT sur une branche preexistante n ecrase rien : il est ecrit
# SANS --readme, contrairement a un contenu qui existe deja et diverge. La spec
# le precise depuis sa correction du 2026-08-10 (commit 125f9f9) — sans cette
# distinction, --fix seul ne peut jamais amener aux normes un depot qui n a
# jamais eu de README, ce qui est le cas de tous les depots existants.
zc 'rm=$(printf "dev\tabsent")
    _work_cfg_build_plan demo-x dev 0 dev "dev" "" "$rm"' \
    | assert_equals "README preexistant ABSENT sans --readme : ecrit quand meme" \
"$(printf 'readme_write\tdev')"

echo
echo "== planificateur : branches hors norme =="

zc 'br=$(print -l master dev qlf pprd prd)
    rules=$(printf "pprd\t40\t40\tfalse\nprd\t40\t40\tfalse")
    rm=$(printf "dev\tok\nqlf\tok\npprd\tok\nprd\tok")
    _work_cfg_build_plan demo-x dev,qlf,pprd,prd 0 master "$br" "$rules" "$rm"' \
    | assert_equals "master : bascule du defaut puis suppression" \
"$(printf 'default_set\tdev\nmaster_delete\tmaster')"

zc 'br=$(print -l dev feature/x config/y unprotected); rm=$(printf "dev\tok")
    _work_cfg_build_plan demo-x dev 0 dev "$br" "" "$rm"' \
    | assert_equals "feature/config/unprotected : conservees, signalees" \
"$(printf 'warn\tbranche hors norme conservee : feature/x\nwarn\tbranche hors norme conservee : config/y\nwarn\tbranche hors norme conservee : unprotected')"

echo
echo "== appartenance litterale, pas de glob =="

# [(I) traite le motif comme un glob ; [(Ie) le traite comme une chaine litterale.
# Sans le e, "p*" matcherait pprd au lieu d etre rejete comme env inconnu.
zc '_work_cfg_normalize_envs "p*" >/dev/null 2>&1 || print refuse' \
    | assert_equals "motif p* rejete : comparaison litterale, pas de glob" "refuse"

# Une regle de protection nommee config/* (un joker GitLab valide) ne doit pas
# etre appariee par glob a la branche config/y : elle reste orpheline tant
# qu aucune branche ne porte litteralement ce nom.
zc 'br=$(print -l dev config/y)
    rules=$(printf "config/*\t40\t40\tfalse")
    rm=$(printf "dev\tok")
    pat=$(printf "rule_delete_orphan\tconfig/*")
    _work_cfg_build_plan demo-x dev 0 dev "$br" "$rules" "$rm" | grep -Fc "$pat"' \
    | assert_equals "regle config/* : orpheline malgre config/y (comparaison litterale)" "1"

echo
echo "== parsing d options =="

zc 'work_config_repo --help | head -1' \
    | assert_equals "aide disponible" "Usage: work_config_repo [<repo>] [options]"

# Le piege zsh : un flag a valeur en dernier argument. Sous `set -u` en bash, shift 2
# echoue ; en zsh il boucle a l infini. Le timeout est la garde du test.
# _ui_msg_fail ecrit sur stdout (core/ui.zsh, cf. plus haut) : rediriger seulement
# stderr laisserait fuiter son message et head -1 capturerait la mauvaise ligne.
( zc 'work_config_repo --envs >/dev/null 2>&1; print "rc=$?"' & sleep 5; kill %1 2>/dev/null ) \
    | head -1 | assert_equals "--envs en dernier argument ne boucle pas" "rc=1"

( zc 'work_config_repo --bu >/dev/null 2>&1; print "rc=$?"' & sleep 5; kill %1 2>/dev/null ) \
    | head -1 | assert_equals "--bu en dernier argument ne boucle pas" "rc=1"

zc 'work_config_repo --bu blg --app demoapp technical-assets >/dev/null 2>&1; print "rc=$?"' \
    | assert_equals "technical-assets nomme explicitement : rc=1" "rc=1"

zc 'work_config_repo --zzz >/dev/null 2>&1; print "rc=$?"' \
    | assert_equals "option inconnue : rc=1" "rc=1"

zc 'work_config_repo --bu blg --app demoapp --envs uat demo-x >/dev/null 2>&1; print "rc=$?"' \
    | assert_equals "env inconnu : rc=1" "rc=1"

# Hors du chemin canonique et sans flags : refus, sans reseau.
zc 'cd "$TMPDIR" 2>/dev/null || cd /
    work_config_repo >/dev/null 2>&1; print "rc=$?"' \
    | assert_equals "cible indeterminable : rc=1" "rc=1"

echo
echo "== la cause d un refus est dite =="

# _work_cfg_normalize_envs echoue via un $( ) : sans reemission explicite du
# message par work_config_repo, --envs uat echouerait en silence (rc=1 mais
# rien sur stdout). On ne redirige pas stdout ici, c est justement ce qu on mesure.
zc 'work_config_repo --bu blg --app demoapp --envs uat demo-x 2>/dev/null | grep -c "env inconnu"' \
    | assert_equals "cause du refus --envs uat affichee" "1"

# ${envs_csv:-defaut} confondrait --envs absent et --envs "" : la valeur vide
# explicite doit rester une erreur, pas retomber sur la norme complete.
zc 'work_config_repo --bu blg --app demoapp --envs "" demo-x >/dev/null 2>&1; print "rc=$?"' \
    | assert_equals "--envs vide explicitement refuse" "rc=1"

echo
echo "== couche reseau =="

zc '_work_cfg_enc "blg/applications/demoapp/configurations/demo-front"' \
    | assert_equals "chemin encode pour l API" "blg%2Fapplications%2Fdemoapp%2Fconfigurations%2Fdemo-front"

zc 'GITLAB_BASE_DOMAIN=forge.exemple.test; _work_cfg_api' \
    | assert_equals "URL de l API construite" "https://forge.exemple.test/api/v4"

zc 'unset GITLAB_BASE_DOMAIN GITLAB_TOKEN
    HOME=$TMPDIR
    _work_cfg_require >/dev/null 2>&1; print "rc=$?"' \
    | assert_equals "sans domaine ni token : refus" "rc=1"

# Le point qui compte : hors reseau, la commande echoue vite, elle ne pend pas.
zc 'GITLAB_BASE_DOMAIN=127.0.0.1:9 GITLAB_TOKEN=x
    SECONDS=0
    _work_cfg_json GET version >/dev/null 2>&1
    rc=$?
    print "rc=$rc borne=$(( SECONDS <= 10 ))"' \
    | assert_equals "hote injoignable : echec immediat, pas de pendaison" "rc=1 borne=1"

zc 'GITLAB_BASE_DOMAIN=127.0.0.1:9 GITLAB_TOKEN=x
    _work_cfg_json GET version >/dev/null 2>&1
    [[ -n "$_work_cfg_last_error" ]] && print renseigne || print vide' \
    | assert_equals "la cause de l echec est nommee" "renseigne"

# Pas de -k : la commande ne doit jamais desactiver la verification TLS.
# grep -c -- '-k' matcherait n importe quel "-k" y compris a l interieur d un
# mot ou dans un commentaire qui en parle (le fichier en contient un qui
# documente justement l absence du flag). On ecarte les lignes de commentaire
# pur et on exige que -k/--insecure soit un token isole, pas un fragment.
grep -v '^[[:space:]]*#' "$MOD" \
    | grep -cE -- '(^|[^A-Za-z0-9_-])-k([^A-Za-z0-9_-]|$)' \
    | tr -d ' ' | assert_equals "aucun -k dans le module" "0"
grep -v '^[[:space:]]*#' "$MOD" \
    | grep -cE -- '(^|[^A-Za-z0-9_-])--insecure([^A-Za-z0-9_-]|$)' \
    | tr -d ' ' | assert_equals "aucun --insecure dans le module" "0"

echo
echo "== _work_cfg_require : le chemin nominal =="

# Seul l echec etait couvert. Or c est la REUSSITE qui porte la garantie de cette
# tache : le module work ne depend pas de l activation du module gitlab, il source
# lui-meme ~/.gitlab_secrets. Un chemin casse (mauvais fichier, mauvais nom de
# variable, quoting rompu) laisserait toute la suite verte.
zc 'HOME="${WORK_DIR:h}"
    print "GITLAB_TOKEN=x"                        >  "$HOME/.gitlab_secrets"
    print "GITLAB_BASE_DOMAIN=forge.exemple.test" >> "$HOME/.gitlab_secrets"
    unset GITLAB_TOKEN GITLAB_BASE_DOMAIN
    _work_cfg_require >/dev/null 2>&1
    rc=$?
    rm -f "$HOME/.gitlab_secrets"
    print "rc=$rc token=${GITLAB_TOKEN:-vide}"' \
    | assert_equals "la garde source elle-meme ~/.gitlab_secrets" "rc=0 token=x"

echo
echo "== _work_cfg_json : la cause de l echec est nommee =="

# _work_cfg_curl appelle `command curl`, qu une fonction du meme nom ne peut pas
# intercepter. On stube donc _work_cfg_curl, qui est bien une fonction. Ces cas
# couvrent la logique de _work_cfg_json — extraction du code, garde <->, branche
# >= 400 — qu aucune assertion n exercait : le port ferme rend la main avant.
zc '_work_cfg_curl() { print 401; print corps }
    _work_cfg_json GET projects/1 >/dev/null 2>&1
    print -r -- "$_work_cfg_last_error"' | grep -o "GITLAB_TOKEN refuse" \
    | assert_equals "401 : la cause nommee est le token" "GITLAB_TOKEN refuse"

zc '_work_cfg_curl() { print 403; print corps }
    _work_cfg_json GET projects/1 >/dev/null 2>&1
    print -r -- "$_work_cfg_last_error"' | grep -o "droits insuffisants" \
    | assert_equals "403 : la cause nommee est les droits" "droits insuffisants"

zc '_work_cfg_curl() { print "<html>portail</html>" }
    _work_cfg_json GET projects/1 >/dev/null 2>&1
    print -r -- "$_work_cfg_last_error"' | grep -o "proxy s est interpose" \
    | assert_equals "reponse sans code HTTP : le proxy est nomme" "proxy s est interpose"

# Le corps n est plus sur stdout mais dans _work_cfg_body (critique de revue : un
# $( ) est un sous-shell, cf. plus haut) — _work_cfg_json ne rend plus rien du tout
# sur stdout, succes compris.
zc '_work_cfg_curl() { print 200; print "{\"id\":42}" }
    _work_cfg_json GET projects/1
    print -r -- "$_work_cfg_body"' \
    | assert_equals "200 : le corps va dans _work_cfg_body, plus sur stdout" '{"id":42}'

# Un portail interpose peut refleter les en-tetes de la requete dans son corps
# d erreur. Le token ne doit pas ressortir dans la cause.
zc 'GITLAB_TOKEN=jeton-secret-abc
    _work_cfg_curl() { print 403; print "refuse: PRIVATE-TOKEN jeton-secret-abc" }
    _work_cfg_json GET projects/1 >/dev/null 2>&1
    print -r -- "$_work_cfg_last_error"' | grep -c "jeton-secret-abc" | tr -d ' ' \
    | assert_equals "le token n est jamais reflete dans la cause" "0"

echo
echo "== _work_cfg_collect : le dispatch 404 qui etait mort =="

# _work_cfg_collect n avait AUCUNE assertion directe. C est par ce trou que le
# critique de revue est passe : _work_cfg_json perdait sa cause a travers un $( ),
# donc `[[ "$_work_cfg_last_error" == HTTP 404* ]]` ne matchait jamais et le
# dispatch 404 -> 2 n etait jamais atteint en production, seulement en apparence
# couvert par des tests qui stubaient plus haut que ce chemin. On stube
# _work_cfg_curl (pas _work_cfg_json) pour exercer la vraie fonction bout en bout.

zc '_work_cfg_curl() { print 404; print "{}" }
    _work_cfg_collect blg demoapp demo-x dev
    print "rc=$?"' \
    | assert_equals "collect sur 404 : rc=2, le dispatch reagit enfin" "rc=2"

# Un 403 en lecture de README doit arreter net, JAMAIS classer « divergent » : sous
# --fix --readme, classer un refus comme divergent le ferait ecraser un README
# valide qu on n a simplement pas pu relire. C est le chemin destructif que le
# critique masquait ; il n avait jamais eu sa propre assertion committee.
#
# Le stub distingue par le CHEMIN de l appel, jamais par un compteur : _work_cfg_curl
# est appelee via un $( ) dans _work_cfg_json (cf. critique 1 plus haut), donc tout
# etat qu un compteur essaierait de faire survivre entre deux appels serait perdu
# au meme sous-shell — la premiere version de ce test l a demontre en tombant sur
# elle-meme (le compteur restait bloque a 1, jq recevait le mauvais corps).
zc '_work_cfg_curl() {
        case "$2" in
            *repository/branches\?*)     print 200; print "[{\"name\":\"dev\"}]" ;;
            *protected_branches\?*)      print 200; print "[]" ;;
            *repository/files/*)         print 403; print "{}" ;;
            *)                            print 200; print "{\"id\":42,\"default_branch\":\"dev\"}" ;;
        esac
    }
    _work_cfg_collect blg demoapp demo-x dev >/dev/null 2>&1
    rc=$?
    print "rc=$rc readmes=${_work_cfg_readmes:-vide} divergent=$(print -r -- "$_work_cfg_readmes" | grep -c divergent)"' \
    | assert_equals "403 sur le README : rc=1, jamais classe divergent" \
"rc=1 readmes=vide divergent=0"

# Les trois etats a la fois, dans un seul passage : ok (contenu conforme), absent
# (404), divergent (200 mais contenu different). Rien avant ceci ne verifiait la
# classification elle-meme, seulement des morceaux isoles (curl, json, readme_content).
zc '_work_cfg_curl() {
        case "$2" in
            *repository/branches\?*)      print 200; print "[{\"name\":\"dev\"},{\"name\":\"qlf\"},{\"name\":\"pprd\"}]" ;;
            *protected_branches\?*)       print 200; print "[]" ;;
            *repository/files/*ref=dev)   print 200; print "# demo-x dev" ;;
            *repository/files/*ref=qlf)   print 404; print "{}" ;;
            *repository/files/*ref=pprd)  print 200; print "contenu different" ;;
            *)                             print 200; print "{\"id\":42,\"default_branch\":\"dev\"}" ;;
        esac
    }
    _work_cfg_collect blg demoapp demo-x dev,qlf,pprd
    print "rc=$?"
    print -r -- "$_work_cfg_readmes"' \
    | assert_equals "collect classe ok, absent et divergent" \
"$(printf 'rc=0\ndev\tok\nqlf\tabsent\npprd\tdivergent')"

echo
echo "== _work_cfg_run : les deux codes de sortie qui manquaient =="

# _work_cfg_run n avait pas plus d assertion que _work_cfg_collect : rien ne
# verifiait qu il rend jamais 0 ou 2. On stube _work_cfg_collect elle-meme —
# deja testee ci-dessus — pour piloter le plan sans reseau.

zc 'GITLAB_TOKEN=x GITLAB_BASE_DOMAIN=exemple.test
    _work_cfg_collect() {
        typeset -g _work_cfg_pid=1 _work_cfg_default=dev \
            _work_cfg_branches=$(printf "dev\nqlf\npprd\nprd") \
            _work_cfg_rules=$(printf "pprd\t40\t40\tfalse\nprd\t40\t40\tfalse") \
            _work_cfg_readmes=$(printf "dev\tok\nqlf\tok\npprd\tok\nprd\tok")
        return 0
    }
    _work_cfg_run blg demoapp demo-front dev,qlf,pprd,prd 0 0 >/dev/null 2>&1
    print "rc=$?"' \
    | assert_equals "collect stube conforme, sans --fix : rc=0" "rc=0"

zc 'GITLAB_TOKEN=x GITLAB_BASE_DOMAIN=exemple.test
    _work_cfg_collect() {
        typeset -g _work_cfg_pid=1 _work_cfg_default=dev \
            _work_cfg_branches=$(printf "dev\nprd") \
            _work_cfg_rules=$(printf "prd\t40\t40\tfalse") \
            _work_cfg_readmes=$(printf "dev\tok\nprd\tok")
        return 0
    }
    _work_cfg_run blg demoapp demo-front dev,qlf,prd 0 0 >/dev/null 2>&1
    print "rc=$?"' \
    | assert_equals "collect stube avec ecarts, sans --fix : rc=2" "rc=2"

echo
echo "== rendu du rapport =="

zc "_work_cfg_render demo-x '' | tail -1" \
    | assert_equals "plan vide : conformite annoncee" "  Rien a faire — le repo est conforme."

zc "_work_cfg_render demo-docs \"\$(printf 'branch_create\tqlf\tdev\nreadme_write\tqlf')\" | grep -c '^  '" \
    | assert_equals "deux actions rendues sur deux lignes" "2"

zc "_work_cfg_render demo-docs \"\$(printf 'branch_create\tqlf\tdev')\" | grep -o 'creer branche qlf depuis dev'" \
    | assert_equals "creation de branche libellee" "creer branche qlf depuis dev"

zc "_work_cfg_render demo-x \"\$(printf 'protect_replace\tprd')\" | grep -o 'fenetre de non-protection'" \
    | assert_equals "le remplacement de protection annonce sa fenetre" "fenetre de non-protection"

zc "_work_cfg_render demo-x \"\$(printf 'master_delete\tmaster')\" | grep -o 'sous reserve du merge-base'" \
    | assert_equals "la suppression de master annonce sa garde" "sous reserve du merge-base"

zc "_work_cfg_count_actions \"\$(printf 'branch_create\tqlf\tdev\nwarn\tblabla\nreadme_write\tqlf')\"" \
    | assert_equals "les avertissements ne comptent pas comme des actions" "2"

# La distinction qui evite d annoncer « conforme » a un depot en ecart.
zc "_work_cfg_count_ecarts \"\$(printf 'ecart\tREADME de dev absent\nwarn\tblabla\nreadme_write\tqlf')\"" \
    | assert_equals "seules les lignes ecart comptent comme ecarts" "1"

zc "_work_cfg_count_actions \"\$(printf 'ecart\tREADME de dev absent\nwarn\tblabla')\"" \
    | assert_equals "un ecart n est pas une action" "0"

zc "_work_cfg_render demo-x \"\$(printf 'ecart\tREADME de dev absent')\" | tail -1" \
    | assert_equals "un plan sans action mais avec ecart n annonce pas la conformite" \
"  Aucune action applicable — 1 ecart(s) exigent --readme."

zc "_work_cfg_render demo-x \"\$(printf 'warn\tbranche hors norme conservee : prd')\" | tail -1" \
    | assert_equals "une simple observation laisse annoncer la conformite" \
"  Rien a faire — le repo est conforme."

echo
echo "== dialogue y/N/u =="

zc 'print "" | _work_cfg_read_answer' \
    | assert_equals "entree vide : refus par defaut" "n"

zc 'print "y" | _work_cfg_read_answer' | assert_equals "y accepte" "y"
zc 'print "Y" | _work_cfg_read_answer' | assert_equals "Y accepte (casse ignoree)" "y"
zc 'print "u" | _work_cfg_read_answer' | assert_equals "u accepte" "u"
zc 'print "n" | _work_cfg_read_answer' | assert_equals "n accepte" "n"
zc 'print "zzz" | _work_cfg_read_answer' | assert_equals "reponse inconnue : refus" "n"

# stdin ferme (execution non interactive) : refus, jamais d application implicite.
zc '_work_cfg_read_answer < /dev/null' \
    | assert_equals "stdin ferme : refus" "n"

echo
echo "== la derniere barriere avant ecriture =="

# Les assertions ci-dessus ne couvrent que le LECTEUR d entree. C est
# _work_cfg_confirm_and_apply qui decide si _work_cfg_apply est appelee, et la
# tache 8 y branche une suppression de branche : elle merite ses propres cas.
# Le stub trace sur stderr — une variable ne survivrait pas au sous-shell du pipe.

zc '_work_cfg_apply() { print -u2 APPLIQUE; return 0 }
    out=$(print "y" | _work_cfg_confirm_and_apply demo-x dev 0 \
          "$(printf "branch_create\tqlf\tdev")" 2>&1 >/dev/null)
    print "trace=${out:-vide}"' \
    | assert_equals "reponse y : l application est appelee" "trace=APPLIQUE"

zc '_work_cfg_apply() { print -u2 APPLIQUE; return 0 }
    out=$(print "n" | _work_cfg_confirm_and_apply demo-x dev 0 \
          "$(printf "branch_create\tqlf\tdev")" 2>&1 >/dev/null)
    rc=$?
    print "rc=$rc trace=${out:-vide}"' \
    | assert_equals "reponse n : rien n est applique" "rc=2 trace=vide"

zc '_work_cfg_apply() { print -u2 APPLIQUE; return 0 }
    out=$(_work_cfg_confirm_and_apply demo-x dev 0 \
          "$(printf "branch_create\tqlf\tdev")" </dev/null 2>&1 >/dev/null)
    rc=$?
    print "rc=$rc trace=${out:-vide}"' \
    | assert_equals "stdin ferme : aucune application" "rc=2 trace=vide"

# Une saisie d envs fautive dans le wizard doit dire pourquoi, pas se taire.
zc 'out=$(printf "u\nuat\nn\n" | _work_cfg_confirm_and_apply demo-x dev 0 \
          "$(printf "branch_create\tqlf\tdev")" 2>&1)
    print -r -- "$out" | grep -c "env inconnu"' \
    | assert_equals "une saisie d envs fautive dit pourquoi" "1"

echo
echo "== garde merge-base =="

zc '_work_cfg_sha_contained abc123 abc123 && print sur || print refuse' \
    | assert_equals "merge-base egal au SHA : suppression sure" "sur"

zc '_work_cfg_sha_contained abc123 def456 && print sur || print refuse' \
    | assert_equals "merge-base different : suppression refusee" "refuse"

zc '_work_cfg_sha_contained "" "" && print sur || print refuse' \
    | assert_equals "SHA vides : suppression refusee" "refuse"

zc '_work_cfg_sha_contained abc123 "" && print sur || print refuse' \
    | assert_equals "merge-base vide : suppression refusee" "refuse"

echo
echo "== ordre d application =="

# L API refuse de supprimer la branche par defaut, et de supprimer une branche
# protegee : l ordre n est donc pas libre.
zc "_work_cfg_sort_plan \"\$(printf 'master_delete\tmaster\nprotect_create\tprd\nbranch_create\tqlf\tdev\ndefault_set\tdev\nreadme_write\tqlf\nunprotect\tqlf\nrule_delete_orphan\tzzz')\" | cut -f1" \
    | assert_equals "sept etapes remises dans l ordre de la spec" \
"$(printf 'branch_create\ndefault_set\nunprotect\nreadme_write\nprotect_create\nrule_delete_orphan\nmaster_delete')"

zc "_work_cfg_sort_plan \"\$(printf 'warn\tblabla\nbranch_create\tqlf\tdev')\" | cut -f1" \
    | assert_equals "les avertissements sortent en fin de plan" \
"$(printf 'branch_create\nwarn')"

echo
echo "== application : les etapes partent vraiment =="

# Ce que ces cas ferment : ${(f)$(...)} non cite aplatit tabulations et retours ligne,
# la boucle ne tourne qu une fois, aucun case ne matche, et _work_cfg_apply rend 0
# sans avoir rien applique. Les assertions sur _work_cfg_sort_plan ne pouvaient pas
# le voir — elles ne touchent pas le code qui ecrit.
zc '_work_cfg_json() { print -u2 "$1 $2"; return 0 }
    _work_cfg_pid=42; _work_cfg_envs_current=dev,qlf,pprd,prd
    plan=$(printf "protect_create\tprd\nbranch_create\tqlf\tdev")
    out=$(_work_cfg_apply demo-x "$plan" 2>&1 >/dev/null)
    print -r -- "$out" | grep -c "^POST"' \
    | assert_equals "un plan a deux etapes emet deux appels" "2"

zc '_work_cfg_json() { print -u2 "$2"; return 0 }
    _work_cfg_pid=42; _work_cfg_envs_current=dev
    plan=$(printf "protect_create\tprd\nbranch_create\tqlf\tdev")
    out=$(_work_cfg_apply demo-x "$plan" 2>&1 >/dev/null)
    print -r -- "$out" | head -1 | grep -o "repository/branches"' \
    | assert_equals "la creation de branche precede la protection" "repository/branches"

zc '_work_cfg_json() { print -u2 "$1 $2"; return 0 }
    _work_cfg_is_merged() { return 1 }
    _work_cfg_pid=42; _work_cfg_envs_current=dev
    out=$(_work_cfg_apply demo-x "$(printf "master_delete\tmaster")" 2>&1 >/dev/null); rc=$?
    print "rc=$rc suppr=$(print -r -- "$out" | grep -c "repository/branches")"' \
    | assert_equals "garde refusant : aucune suppression, rc=2" "rc=2 suppr=0"

zc '_work_cfg_json() { print -u2 "$1 $2"; return 0 }
    _work_cfg_is_merged() { return 2 }
    _work_cfg_pid=42; _work_cfg_envs_current=dev
    out=$(_work_cfg_apply demo-x "$(printf "master_delete\tmaster")" 2>&1 >/dev/null); rc=$?
    print "rc=$rc suppr=$(print -r -- "$out" | grep -c "repository/branches")"' \
    | assert_equals "merge-base inverifiable : arret, rc=1, rien de supprime" "rc=1 suppr=0"

zc '_work_cfg_json() { [[ "$1" == POST ]] && return 1; return 0 }
    _work_cfg_pid=42; _work_cfg_envs_current=dev
    _work_cfg_apply demo-x "$(printf "branch_create\tqlf\tdev\nprotect_create\tprd")" >/dev/null 2>&1
    print "rc=$?"' \
    | assert_equals "une etape en echec arrete la sequence" "rc=1"

# IMPORTANT 3 de la revue finale : le DELETE d un protect_replace passait, le POST
# de remplacement echouait en 403, et prd restait deprotegee EN SILENCE — rien ne
# le disait, alors que l avertissement prealable ne promet qu une fenetre BREVE.
# Le motif existe deja pour master_delete ; protect_replace doit le porter aussi.
zc '_work_cfg_json() { [[ "$1" == POST ]] && return 1; return 0 }
    _work_cfg_pid=42
    out=$(_work_cfg_apply demo-x "$(printf "protect_replace\tprd")" 2>&1); rc=$?
    print "rc=$rc deprotegee=$(print -r -- "$out" | grep -c "restee DEPROTEGEE")"' \
    | assert_equals "protect_replace : POST en echec, prd nommee DEPROTEGEE" "rc=1 deprotegee=1"

# MINEUR :712 de la revue finale : default_set etait le dernier corps JSON construit
# par interpolation. Round-trip par jq, comme les autres corps de ce module.
zc '_work_cfg_json() { [[ "$1" == PUT ]] && print -r -u2 -- "$3"; return 0 }
    _work_cfg_pid=42
    out=$(_work_cfg_apply demo-x "$(printf "default_set\tdev")" 2>&1 >/dev/null)
    print -r -- "$out" | jq -r ".default_branch"' \
    | assert_equals "bascule du defaut : corps JSON construit par jq" "dev"

echo
echo "== la garde elle-meme, sans stub =="

# Les cas ci-dessus stubent _work_cfg_is_merged pour piloter _work_cfg_apply. Son
# CORPS, lui, n etait exerce par rien — et c est lui qui decide d une suppression.
# Un return 0 sur echec d API ferait partir la suppression de master : c est le
# chemin de perte de commits, il merite ses propres cas.
zc '_work_cfg_json() { return 1 }
    _work_cfg_last_error="HTTP 500"
    _work_cfg_is_merged 42 master dev; print "rc=$?"' \
    | assert_equals "API en echec : la garde rend 2, jamais 0" "rc=2"

# _work_cfg_json rend maintenant son corps par la globale _work_cfg_body, plus par
# stdout (critique de revue : un $( ) est un sous-shell, cf. plus haut). Le stub
# doit donc deposer le corps a l endroit ou _work_cfg_is_merged va le lire.
zc '_work_cfg_json() { typeset -g _work_cfg_body="{}"; return 0 }
    _work_cfg_is_merged 42 master dev; print "rc=$?"' \
    | assert_equals "reponse sans SHA : la garde ne sait pas, jamais 1" "rc=2"

zc '_work_cfg_json() { typeset -g _work_cfg_body="{\"commit\":{\"id\":\"abc\"},\"id\":\"abc\"}"; return 0 }
    _work_cfg_is_merged 42 master dev; print "rc=$?"' \
    | assert_equals "SHA egal au merge-base : la garde accepte" "rc=0"

# Le consentement doit etre eclaire : retirer la protection de master fait partie
# de sa suppression, et l utilisateur doit le lire AVANT de taper y, pas apres.
zc '_work_cfg_render demo-x "$(printf "master_delete\tmaster")" | grep -o "sa protection sera retiree"' \
    | assert_equals "le plan annonce le retrait de protection avant le y" "sa protection sera retiree"

echo
echo "== chemin local de destination =="

zc '_work_cfg_local_path blg demoapp demo-front' \
    | assert_equals "chemin canonique reconstruit" "$TEST_TMPDIR/work/blg/applications/demoapp/configurations/demo-front"

# Aller-retour : ce que _work_cfg_local_path produit, _work_cfg_parse_path le relit.
zc '_work_cfg_parse_path "$(_work_cfg_local_path blg demoapp demo-front)"' \
    | assert_equals "aller-retour chemin stable" "$(printf 'blg\tdemoapp\tdemo-front')"

zc 'p=$(_work_cfg_local_path tsc autreapp demo-api); _work_cfg_parse_path "$p"' \
    | assert_equals "aller-retour sur une autre BU" "$(printf 'tsc\tautreapp\tdemo-api')"

echo
echo "== creation : la sequence distante, sans reseau =="

# Les trois cas ci-dessus couvrent une fonction de chemin. _work_cfg_create, elle,
# est une sequence multi-etapes qui cree de l etat distant : c est elle qui merite
# des cas. On stube _work_cfg_json, git et cd, et on lit la trace.
#
# L assertion d ordre compare la SEQUENCE ENTIERE, pas sa premiere ligne : dev n est
# jamais protegee, donc « le premier README precede la premiere protection » est vrai
# quel que soit l ordre des boucles. Une regression deplacant les protections avant
# la boucle des branches passerait — c est justement ce que le code met en garde.
#
# _work_cfg_json rend maintenant son corps par _work_cfg_body, plus par stdout : les
# stubs ci-dessous le deposent dans cette globale (typeset -g), pas par un `print`
# qu aucun appelant ne lit plus.
#
# La creation demande desormais une confirmation avant le premier POST (cf. plan) :
# un groupe injoignable echoue avant de l atteindre (rien a piper), les sequences
# qui reussissent recoivent leur "y" via un pipe explicite — jamais d entree
# implicite, jamais de stdin herite en silence.

zc '_work_cfg_json() { print -u2 "APPEL $1 $2"; return 1 }
    _work_cfg_last_error="HTTP 404"
    out=$(_work_cfg_create blg demoapp demo-front dev 2>&1); rc=$?
    print "rc=$rc projet=$(print -r -- "$out" | grep -c "APPEL POST projects") cause=$(print -r -- "$out" | grep -c "HTTP 404")"' \
    | assert_equals "groupe injoignable : aucun projet cree, cause dite" "rc=1 projet=0 cause=1"

zc '_work_cfg_json() {
        case "$2" in
            groups/*) typeset -g _work_cfg_body="{\"id\":7}" ;;
            projects) typeset -g _work_cfg_body="{\"id\":42,\"http_url_to_repo\":\"https://exemple.test/x.git\"}" ;;
            *)        typeset -g _work_cfg_body="{}" ;;
        esac
        return 0
    }
    _work_cfg_write_readme() { print -u2 "README $3"; return 0 }
    _work_cfg_protect()      { print -u2 "PROTECT $2"; return 0 }
    git() { return 0 }
    cd()  { return 0 }
    print y | _work_cfg_create blg demoapp demo-front dev,prd 2>&1 >/dev/null \
      | grep -E "^README|^PROTECT"' \
    | assert_equals "chaque README precede la protection de sa branche" \
"$(printf 'README dev\nREADME prd\nPROTECT prd')"

# IMPORTANT 4 de la revue finale : le clone final ignorait la mecanique
# d authentification deja en place pour les clones existants (scripts/clone-projects.sh)
# et faisait un `git clone` nu sur une URL interne — invite interactive ou echec, au
# milieu d une sequence qui a deja cree du projet, des branches et des regles.
zc '_work_cfg_json() {
        case "$2" in
            groups/*) typeset -g _work_cfg_body="{\"id\":7}" ;;
            projects) typeset -g _work_cfg_body="{\"id\":42,\"http_url_to_repo\":\"https://exemple.test/x.git\"}" ;;
            *)        typeset -g _work_cfg_body="{}" ;;
        esac
        return 0
    }
    _work_cfg_write_readme() { return 0 }; _work_cfg_protect() { return 0 }
    GITLAB_TOKEN=jeton-test
    git() { print -u2 "GIT $*"; return 0 }
    cd() { return 0 }
    out=$(print y | _work_cfg_create blg demoapp demo-front dev 2>&1 >/dev/null)
    print -r -- "$out" | grep -c "PRIVATE-TOKEN: jeton-test"' \
    | assert_equals "le clone reutilise le token via http.extraheader" "1"

zc '_work_cfg_json() {
        case "$2" in
            groups/*) typeset -g _work_cfg_body="{\"id\":7}" ;;
            projects) typeset -g _work_cfg_body="{\"id\":42,\"http_url_to_repo\":\"https://exemple.test/x.git\"}" ;;
            *)        return 1 ;;
        esac
        return 0
    }
    _work_cfg_last_error="HTTP 403"
    _work_cfg_write_readme() { return 1 }
    out=$(print y | _work_cfg_create blg demoapp demo-front dev,prd 2>&1); rc=$?
    print "rc=$rc partiel=$(print -r -- "$out" | grep -c "existe desormais sur la forge")"' \
    | assert_equals "echec apres creation : l etat partiel est nomme" "rc=1 partiel=1"

# L injection JSON. Le discriminant est .name, PAS .visibility : les cles dupliquees
# se resolvent en « derniere gagne » et visibility vaut internal dans les deux cas,
# donc l assertion serait aveugle. Sous interpolation brute .name est tronque a « x » ;
# sous jq -n --arg il arrive entier.
zc '_work_cfg_json() { [[ "$2" == projects ]] && print -r -u2 -- "$3"; typeset -g _work_cfg_body="{\"id\":1}"; return 0 }
    _work_cfg_write_readme() { return 0 }; _work_cfg_protect() { return 0 }
    git() { return 0 }; cd() { return 0 }
    out=$(print y | _work_cfg_create blg demoapp '"'"'x","visibility":"public'"'"' dev 2>&1 >/dev/null)
    print -r -- "$out" | jq -r ".name"' \
    | assert_equals "un nom hostile arrive entier, non tronque par l interpolation" \
'x","visibility":"public'

echo
echo "== creation : la confirmation qui manquait avant le premier POST =="

# IMPORTANT 2 de la revue finale : _work_cfg_create ecrivait sur la forge dans la
# foulee du rc=2, sans jamais demander. Masque par le critique 1 (le dispatch 404
# etait mort, donc ce chemin n etait jamais atteint en production) : le corriger
# active l autre. Le groupe existe (id connu) ; seule la confirmation separe
# encore la lecture de la premiere ecriture.

zc '_work_cfg_json() { print -u2 "APPEL $1 $2"; typeset -g _work_cfg_body="{\"id\":7}"; return 0 }
    out=$(print n | _work_cfg_create blg demoapp demo-front dev 2>&1); rc=$?
    print "rc=$rc post=$(print -r -- "$out" | grep -c "APPEL POST")"' \
    | assert_equals "n au prompt de creation : aucun POST, rc=2" "rc=2 post=0"

zc '_work_cfg_json() { print -u2 "APPEL $1 $2"; typeset -g _work_cfg_body="{\"id\":7}"; return 0 }
    _work_cfg_write_readme() { return 0 }; _work_cfg_protect() { return 0 }
    git() { return 0 }; cd() { return 0 }
    out=$(print y | _work_cfg_create blg demoapp demo-front dev 2>&1); rc=$?
    print "rc=$rc post=$(print -r -- "$out" | grep -c "APPEL POST projects")"' \
    | assert_equals "y au prompt de creation : la sequence part, rc=0" "rc=0 post=1"

# Stdin ferme (execution non interactive) doit refuser, comme partout ailleurs
# dans ce module : jamais d application implicite.
zc '_work_cfg_json() { print -u2 "APPEL $1 $2"; typeset -g _work_cfg_body="{\"id\":7}"; return 0 }
    out=$(_work_cfg_create blg demoapp demo-front dev </dev/null 2>&1); rc=$?
    print "rc=$rc post=$(print -r -- "$out" | grep -c "APPEL POST")"' \
    | assert_equals "stdin ferme : refus, aucune creation" "rc=2 post=0"

# Meme garantie sur le corps du commit README, un appel plus loin : $repo y entre
# aussi, et il n y a aucune raison que la creation soit la seule protegee.
zc '_work_cfg_curl() { print 404 }
    _work_cfg_json() { [[ "$2" == *repository/commits ]] && print -r -u2 -- "$3"; print "{}"; return 0 }
    out=$(_work_cfg_write_readme 42 '"'"'x","x":"y'"'"' dev 2>&1 >/dev/null)
    print -r -- "$out" | jq -r ".commit_message"' \
    | assert_equals "le message de commit encaisse un nom hostile" \
'chore: normalise le README (x","x":"y dev)'

echo
printf '== %s ok, %s echecs ==\n' "$(cat "$TEST_TMPDIR/pass")" "$(cat "$TEST_TMPDIR/fail")"
[[ "$(cat "$TEST_TMPDIR/fail")" == 0 ]]
