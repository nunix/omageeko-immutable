#!/bin/bash
# SLES layer 03 - verify the userland Omarchy tree
source "$(dirname "$(readlink -f "$0")")/../../lib/common.sh"
source "$OMAGEEKO_SLES/lib/userland.sh"
set +e
fail=0; ok() { printf '  \e[32mok\e[0m   %s\n' "$1"; }; bad() { printf '  \e[31mFAIL\e[0m %s\n' "$1"; fail=1; }
reboot_pending && bad "a newer snapshot is waiting for a reboot"
v=$(rpm -q --qf '%{VERSION}-%{RELEASE}' omageeko-sles 2>/dev/null) && ok "omageeko-sles $v" || bad "omageeko-sles not installed"
[[ -f /usr/share/wayland-sessions/omarchy.desktop ]] && ok "session entry" || bad "session entry missing"
[[ -f /etc/pam.d/omarchy-lock-password ]] && ok "lock PAM" || bad "lock PAM missing"
if [[ $(target_dm running) == sddm ]]; then
  rpm -q omageeko-sles-sddm &>/dev/null && ok "omageeko-sles-sddm (Omarchy greeter + theme)" || bad "omageeko-sles-sddm not installed"
  # vendored copy vs the userland tree (drift after an upstream bump)
  for f in omarchy/Main.qml hyprland.lua; do
    up="$OMARCHY_USER_PATH/default/sddm/$f"
    [[ ! -f $up ]] || cmp -s "$up" "/usr/share/sddm/${f/omarchy\//themes/omarchy/}" && ok "SDDM $f matches upstream" ||
      bad "SDDM $f differs from upstream: refresh packages/omageeko-sles/sddm/"
  done
fi
for p in omageeko omageeko-settings omageeko-session; do
  rpm -q "$p" &>/dev/null && bad "$p is installed on the host (option B keeps it in userland)"
done
[[ -f $OMARCHY_USER_PATH/version ]] && ok "OMARCHY_PATH tree: Omarchy $(cat "$OMARCHY_USER_PATH/version")" || bad "no tree at $OMARCHY_USER_PATH"
links=$(find "$OMARCHY_USER_PATH/bin" -maxdepth 1 -type l | wc -l)
(( links == 0 )) && ok "bin/ holds real files ($(ls "$OMARCHY_USER_PATH/bin" | wc -l) commands)" || bad "$links symlinks in bin/"
left=$(grep -rlE '/usr/share/omarchy([^-[:alnum:]_]|$)|/usr/bin/omarchy-' "$OMARCHY_USER_PATH"/{bin,default,shell,config} 2>/dev/null | wc -l)
(( left == 0 )) && ok "no packaged paths left in the tree" || bad "$left files still reference /usr/share/omarchy or /usr/bin/omarchy-"
grep -q 'omageeko-sles: commands live' "$OMARCHY_USER_PATH/default/bash/env-bootstrap" && ok "env-bootstrap puts \$OMARCHY_PATH/bin on PATH" || bad "env-bootstrap not adapted"
out=$(env -i HOME="$HOME" bash -c ". $OMARCHY_USER_PATH/default/bash/env-bootstrap; echo \$OMARCHY_PATH; command -v omarchy-version")
[[ $out == "$OMARCHY_USER_PATH"$'\n'"$OMARCHY_USER_PATH/bin/omarchy-version" ]] && ok "bootstrap resolves OMARCHY_PATH and commands" || bad "bootstrap: $out"
[[ -f $HOME/.config/uwsm/env.d/10-omarchy ]] && ok "uwsm env.d (user)" || bad "uwsm env.d missing"
[[ -f $HOME/.config/systemd/user/omarchy-shell.service || -n $(ls "$HOME"/.config/systemd/user/omarchy-*.service 2>/dev/null) ]] && ok "user units" || bad "user units missing"
grep -qi "JetBrainsMono Nerd Font" <<<"$(fc-list : family)" && ok "font: JetBrainsMono Nerd Font" || bad "JetBrainsMono Nerd Font missing"
# Ghostty bundle: runs, resolves every library (bundled libadwaita via RPATH), integrated
v=$("$GHOSTTY_HOME/bin/ghostty" --version 2>/dev/null | head -1) && ok "Ghostty bundle: $v" || bad "Ghostty bundle does not run"
missing=$(ldd "$GHOSTTY_HOME/bin/ghostty" 2>/dev/null | grep 'not found')
[[ -z $missing ]] && ok "Ghostty libraries all resolve" || bad "Ghostty: $missing"
ldd "$GHOSTTY_HOME/bin/ghostty" | grep -qE "libadwaita-1\.so\.0 => $GHOSTTY_HOME/(bin/\.\./)?lib/" && ok "libadwaita from the bundle (RPATH)" || bad "libadwaita not from the bundle"
rpm -q ghostty &>/dev/null && bad "ghostty RPM installed on the host (it belongs in userland)"
[[ -f $HOME/.local/share/applications/com.mitchellh.ghostty.desktop ]] && ok "Ghostty desktop entry" || bad "Ghostty desktop entry missing"
[[ -f $HOME/.terminfo/x/xterm-ghostty || -f $HOME/.terminfo/78/xterm-ghostty ]] && ok "terminfo xterm-ghostty" || bad "terminfo xterm-ghostty missing"
exit $fail
