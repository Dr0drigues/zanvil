#!/usr/bin/env bash
# Verifie que les themes s ecrivent dans ${XDG_CONFIG_HOME:-~/.config}/zanvil/theme et
# jamais dans les configs (qui peuvent etre des liens Stow vers le depot dotfiles).
# Usage : scripts/tests/theme-dir.test.sh
set -uo pipefail

ROOT="${ZANVIL_DIR:-$HOME/.zanvil}"

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

sum() { shasum "$1" 2>/dev/null | cut -d' ' -f1; }

# Un ZANVIL_DIR jetable : zanvil-theme ecrit .current_theme dedans
Z="$TEST_TMPDIR/zanvil"
mkdir -p "$Z"
cp -R "$ROOT/core" "$ROOT/config" "$Z/"

# Faux starship ; zanvil absent du PATH pour forcer le repli zsh
BIN="$TEST_TMPDIR/bin"
mkdir -p "$BIN"
printf '#!/bin/sh\nexit 0\n' > "$BIN/starship"; chmod +x "$BIN/starship"

H="$TEST_TMPDIR/home"
X="$TEST_TMPDIR/xdg"
TD="$X/zanvil/theme"

zt() {
    rm -rf "$H" "$X"; mkdir -p "$H/.config" "$X"
    eval "${2:-}"
    HOME="$H" XDG_CONFIG_HOME="$X" ZANVIL_DIR="$Z" PATH="${ZT_PATH:-}$BIN:/usr/bin:/bin" zsh -f -c "
        source '$Z/core/ui.zsh'
        source '$Z/core/commands/theme.zsh'
        $1
    " 2>&1
}

echo "_zanvil_theme_dir"
zt '_zanvil_theme_dir' | assert_equals "suit XDG_CONFIG_HOME" "$TD"
HOME="$H" PATH="/usr/bin:/bin" zsh -f -c "unset XDG_CONFIG_HOME; source '$Z/core/commands/theme.zsh'; _zanvil_theme_dir" \
    | assert_equals "defaut ~/.config" "$H/.config/zanvil/theme"

echo "zanvil-theme (starship)"
zt 'zanvil-theme minimal >/dev/null; cmp -s "$ZANVIL_DIR/config/themes/minimal.toml" "$XDG_CONFIG_HOME/zanvil/theme/starship.toml" && echo copie' \
    | assert_equals "ecrit <theme_dir>/starship.toml" "copie"
zt 'zanvil-theme minimal >/dev/null; [[ -e $HOME/.config/starship.toml ]] && echo present || echo absent' \
    | assert_equals "ne cree pas ~/.config/starship.toml" "absent"

OLD='printf "# Starship Theme: ancien\nformat = \"x\"\n" > "$H/.config/starship.toml"'
zt 'zanvil-theme minimal >/dev/null; shasum $HOME/.config/starship.toml | cut -d" " -f1' "$OLD" \
    | assert_equals "starship.toml preexistant intact" \
        "$(printf '# Starship Theme: ancien\nformat = "x"\n' | shasum | cut -d' ' -f1)"
zt 'zanvil-theme minimal | grep -c "starship.toml"' "$OLD" \
    | assert_equals "ancien starship.toml signale" "1"
zt 'zanvil-theme minimal >/dev/null; zanvil-theme minimal | grep -c "starship.toml"' "$OLD" \
    | assert_equals "signale une seule fois" "0"
zt 'zanvil-theme minimal | grep -c "starship.toml"' 'printf "format = \"perso\"\n" > "$H/.config/starship.toml"' \
    | assert_equals "starship.toml perso : pas de proposition" "0"

zt 'zanvil-theme minimal >/dev/null; print -r -- $STARSHIP_CONFIG' \
    | assert_equals "STARSHIP_CONFIG exporte dans le shell courant" "$TD/starship.toml"
zt 'export STARSHIP_CONFIG=/perso.toml; zanvil-theme minimal >/dev/null; print -r -- $STARSHIP_CONFIG' \
    | assert_equals "STARSHIP_CONFIG perso respecte" "/perso.toml"

echo "zanvil-theme (delegation au CLI)"
# Un CLI obsolete ecrit encore ~/.config/starship.toml ; un CLI a jour ecrit <theme_dir>
for v in stale fresh; do
    mkdir -p "$TEST_TMPDIR/cli-$v"
    if [[ $v == stale ]]; then dest='$HOME/.config/starship.toml'; else dest='$XDG_CONFIG_HOME/zanvil/theme/starship.toml'; fi
    cat > "$TEST_TMPDIR/cli-$v/zanvil" <<EOF
#!/bin/sh
[ "\$1 \$2" = "theme apply" ] || exit 0
mkdir -p "\$(dirname "$dest")"
cp "\$ZANVIL_DIR/config/themes/\$3.toml" "$dest"
echo "\$3" > "\$ZANVIL_DIR/.current_theme"
EOF
    chmod +x "$TEST_TMPDIR/cli-$v/zanvil"
done
STALE="$TEST_TMPDIR/cli-stale:"
FRESH="$TEST_TMPDIR/cli-fresh:"
ZT_PATH="$STALE" zt 'zanvil-theme minimal >/dev/null; cmp -s "$ZANVIL_DIR/config/themes/minimal.toml" "$XDG_CONFIG_HOME/zanvil/theme/starship.toml" && echo copie' \
    | assert_equals "CLI obsolete : le fichier genere porte le theme" "copie"
ZT_PATH="$STALE" zt 'zanvil-theme minimal | grep -c "obsolete"' \
    | assert_equals "CLI obsolete : averti" "1"
ZT_PATH="$STALE" zt 'zanvil-theme apply minimal >/dev/null; print -r -- $STARSHIP_CONFIG' \
    | assert_equals "CLI obsolete : STARSHIP_CONFIG exporte (forme apply)" "$TD/starship.toml"
SLINK='mkdir -p "$TEST_TMPDIR/dotfiles"; echo "format = \"dotfiles\"" > "$TEST_TMPDIR/dotfiles/starship.toml"; ln -s "$TEST_TMPDIR/dotfiles/starship.toml" "$H/.config/starship.toml"'
ZT_PATH="$STALE" zt 'zanvil-theme minimal >/dev/null; cat "$HOME/.config/starship.toml"' "$SLINK" \
    | assert_equals "CLI obsolete : starship.toml lie (dotfiles) intact" 'format = "dotfiles"'
ZT_PATH="$FRESH" zt 'zanvil-theme minimal > $HOME/out; grep -c "obsolete" $HOME/out; print -r -- $STARSHIP_CONFIG' \
    | assert_equals "CLI a jour : pas d avertissement" "$(printf '0\n%s' "$TD/starship.toml")"

echo "zanvil-ghostty"
before=$(sum "$Z/config/ghostty/config")
zt 'zanvil-ghostty tokyo-night >/dev/null; cmp -s "$ZANVIL_DIR/config/ghostty/themes/tokyo-night" "$XDG_CONFIG_HOME/zanvil/theme/ghostty" && echo copie' \
    | assert_equals "ecrit <theme_dir>/ghostty" "copie"
sum "$Z/config/ghostty/config" | assert_equals "config versionnee intacte" "$before"
zt 'zanvil-ghostty tokyo-night >/dev/null; zanvil-ghostty list | tr -d "\033" | grep -c "tokyo-night\[0m - Tokyo Night \[[0-9;]*m(actif)"' \
    | assert_equals "list montre le theme actif" "1"

LINK='mkdir -p "$TEST_TMPDIR/dotfiles" "$H/.config/ghostty"; echo "font-size = 13" > "$TEST_TMPDIR/dotfiles/config"; ln -s "$TEST_TMPDIR/dotfiles/config" "$H/.config/ghostty/config"'
zt 'zanvil-ghostty tokyo-night >/dev/null; cat "$HOME/.config/ghostty/config"' "$LINK" \
    | assert_equals "config liee intacte apres theme" "font-size = 13"
zt 'zanvil-ghostty sync | grep -c dotfiles; cat "$HOME/.config/ghostty/config"; [[ -L "$HOME/.config/ghostty/config" ]] && echo lien' "$LINK" \
    | assert_equals "sync : config liee non remplacee" "$(printf '1\nfont-size = 13\nlien')"
zt 'zanvil-ghostty sync >/dev/null; cmp -s "$ZANVIL_DIR/config/ghostty/config" "$HOME/.config/ghostty/config" && echo copie' \
    | assert_equals "sync : copie sans lien" "copie"

echo "hooks : STARSHIP_CONFIG"
zh() {
    rm -rf "$H" "$X"; mkdir -p "$H" "$X"
    eval "${2:-}"
    HOME="$H" XDG_CONFIG_HOME="$X" XDG_CACHE_HOME="$TEST_TMPDIR/cache" ZANVIL_DIR="$Z" \
        PATH="$BIN:/usr/bin:/bin" zsh -f -c "
        source '$Z/core/cache.zsh'
        $1
        source '$Z/core/hooks.zsh' >/dev/null 2>&1
        print -r -- \"\${STARSHIP_CONFIG:-vide}\"
    " 2>&1
}
MK='mkdir -p "$TD"; : > "$TD/starship.toml"'
zh '' "$MK" | assert_equals "exporte le fichier genere" "$TD/starship.toml"
zh 'export STARSHIP_CONFIG=/perso.toml' "$MK" | assert_equals "respecte un STARSHIP_CONFIG existant" "/perso.toml"
zh '' | assert_equals "sans fichier genere : rien" "vide"

echo
echo "  $(cat "$TEST_TMPDIR/pass") ok, $(cat "$TEST_TMPDIR/fail") echec(s)"
[[ $(cat "$TEST_TMPDIR/fail") -eq 0 ]]
