#!/bin/bash
# SLES layer 01b - verify the Hyprland stack

source "$(dirname "$(readlink -f "$0")")/../../lib/common.sh"
set +e
fail=0
ok() { printf '  \e[32mok\e[0m   %s\n' "$1"; }
bad() { printf '  \e[31mFAIL\e[0m %s\n' "$1"; fail=1; }

LAYER_DIR="$OMAGEEKO_SLES/layers/01b-hyprland"

if reboot_pending; then bad "a newer snapshot is waiting for a reboot (results below describe the running one)"; fi

[[ -f $OMAGEEKO_TUKIT_CONF ]] && ok "tukit bind mount ($OMAGEEKO_TUKIT_CONF)" || bad "tukit bind mount missing"
zypper -q --no-refresh lr "$OMAGEEKO_REPO_ALIAS" &>/dev/null && ok "repo $OMAGEEKO_REPO_ALIAS registered" || bad "repo $OMAGEEKO_REPO_ALIAS not registered"

# Every RPM name from omageeko-local that is installed must be the omageeko build
for p in hyprland hyprland-guiutils hyprpicker hyprsunset xdg-desktop-portal-hyprland uwsm; do
  info=$(rpm -q --qf '%{VERSION}-%{RELEASE} %{VENDOR}' "$p" 2>/dev/null)
  if [[ $info == *omageeko* ]]; then ok "$p ${info% *}"; else bad "$p not installed from $OMAGEEKO_REPO_ALIAS (${info:-missing})"; fi
done

# Installed packages match what the repo offers (nothing pending)
pending=$(zypper -q --no-refresh list-updates -r "$OMAGEEKO_REPO_ALIAS" 2>/dev/null | grep -c '^v ')
(( pending == 0 )) && ok "no pending updates from $OMAGEEKO_REPO_ALIAS" || bad "$pending updates pending: rerun install.sh"

# Each lock entry was built at its pinned commit
while read -r n c _; do
  [[ -z $n || $n == \#* ]] && continue
  [[ -f $STAMP_DIR/01b-$n ]] && ok "built: $n@${c:0:12}" || bad "not built: $n (run install.sh)"
done < "$LAYER_DIR/hyprland.lock"

v=$(Hyprland --version 2>/dev/null | head -1)
[[ -n $v ]] && ok "Hyprland runs: $v" || bad "Hyprland --version failed"
for cmd in hyprctl start-hyprland uwsm hyprpicker hyprsunset; do
  command -v "$cmd" &>/dev/null && ok "command: $cmd" || bad "command missing: $cmd"
done
[[ -f /usr/share/wayland-sessions/hyprland-uwsm.desktop || -f /usr/share/wayland-sessions/hyprland.desktop ]] &&
  ok "Hyprland session file" || bad "no Hyprland session file in /usr/share/wayland-sessions"
[[ -x /usr/libexec/xdg-desktop-portal-hyprland || -x /usr/lib/xdg-desktop-portal-hyprland ]] &&
  ok "xdg-desktop-portal-hyprland" || bad "xdg-desktop-portal-hyprland binary missing"

exit $fail
