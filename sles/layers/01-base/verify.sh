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
flatpak info --user org.chromium.Chromium &>/dev/null && ok "flatpak: Chromium (user)" || bad "Flathub Chromium missing"
[[ -x $HOME/.local/bin/chromium && -f $HOME/.local/share/applications/chromium.desktop ]] && ok "chromium command + chromium.desktop alias" || bad "chromium shim/alias missing"
while read -r p; do
  rpm -q "$p" &>/dev/null && bad "host still has $p (replaced by a userland copy)" || ok "host without $p"
done < <(grep -vE '^[[:space:]]*(#|$)' "$LAYER_DIR/host.remove")
xte=$(PATH="$HOME/.local/bin:$PATH" command -v xdg-terminal-exec)
[[ $xte == "$HOME/.local/bin/xdg-terminal-exec" ]] && ok "xdg-terminal-exec from userland" || bad "xdg-terminal-exec resolves to '${xte:-nothing}'"
id=$("$HOME/.local/bin/xdg-terminal-exec" --print-id 2>/dev/null) && ok "default terminal: $id" || bad "xdg-terminal-exec --print-id found no terminal"
exit $fail
