#!/bin/bash
# SLES layer 01 - verify base
source "$(dirname "$(readlink -f "$0")")/../../lib/common.sh"
set +e
fail=0; ok() { printf '  \e[32mok\e[0m   %s\n' "$1"; }; bad() { printf '  \e[31mFAIL\e[0m %s\n' "$1"; fail=1; }
LAYER_DIR="$OMAGEEKO_SLES/layers/01-base"
reboot_pending && bad "a newer snapshot is waiting for a reboot"
while read -r p; do
  rpm -q --whatprovides "$p" &>/dev/null && ok "host: $p" || bad "host package missing: $p"
done < <(grep -vE '^[[:space:]]*(#|$)' "$LAYER_DIR/host.packages")
[[ -x $HOME/.local/bin/mise ]] && ok "mise $($HOME/.local/bin/mise --version | cut -d' ' -f1)" || bad "mise missing in ~/.local/bin"
for t in bat btop eza fd fzf rg zoxide starship fastfetch lazygit gum tldr nvim tree-sitter yt-dlp herdr; do
  [[ -x $HOME/.local/share/mise/shims/$t ]] && ok "mise shim: $t" || bad "mise shim missing: $t"
done
fams=$(fc-list : family)
for f in "Symbols Nerd Font" "Font Awesome"; do grep -qi "$f" <<<"$fams" && ok "font: $f" || bad "font missing: $f"; done
while read -r p; do
  rpm -q "$p" &>/dev/null && bad "host still has $p (replaced by a userland copy)" || ok "host without $p"
done < <(grep -vE '^[[:space:]]*(#|$)' "$LAYER_DIR/host.remove")
xte=$(PATH="$HOME/.local/bin:$PATH" command -v xdg-terminal-exec)
[[ $xte == "$HOME/.local/bin/xdg-terminal-exec" ]] && ok "xdg-terminal-exec from userland" || bad "xdg-terminal-exec resolves to '${xte:-nothing}'"
id=$("$HOME/.local/bin/xdg-terminal-exec" --print-id 2>/dev/null) && ok "default terminal: $id" || bad "xdg-terminal-exec --print-id found no terminal"
# Flathub browsers: shim + alias, and the sandbox must actually start (a stale flags
# symlink made bwrap fail, so the browser never opened: run 5)
while read -r app cmd desktop_id; do
  grep -qx "$app" "$OMAGEEKO_SLES/layers/01-base/user-flatpaks" || continue
  flatpak info --user "$app" &>/dev/null && ok "flatpak: $app (user)" || { bad "Flathub $app missing"; continue; }
  [[ -x $HOME/.local/bin/$cmd && -f $HOME/.local/share/applications/$desktop_id ]] && ok "$cmd command + $desktop_id alias" || bad "$cmd shim / $desktop_id alias missing"
  out=$(flatpak run --user --command=true "$app" 2>&1) && ok "$app sandbox starts" || bad "$app sandbox fails: $out"
done <<'LIST'
org.chromium.Chromium chromium chromium.desktop
com.brave.Browser brave brave-browser.desktop
LIST
exit $fail
