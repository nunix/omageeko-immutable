#!/bin/bash
# SLES layer 04 - verify the user session setup
source "$(dirname "$(readlink -f "$0")")/../../lib/common.sh"
source "$OMAGEEKO_SLES/lib/userland.sh"
set +e
fail=0; ok() { printf '  \e[32mok\e[0m   %s\n' "$1"; }; bad() { printf '  \e[31mFAIL\e[0m %s\n' "$1"; fail=1; }
[[ -f $HOME/.local/state/omageeko/user-provisioned ]] && ok "user provisioned" || bad "user not provisioned"
grep -q 'default/hypr/bootstrap.lua' "$HOME/.config/hypr/hyprland.lua" && ok "Hyprland config loads Omarchy's bootstrap" || bad "~/.config/hypr/hyprland.lua is not Omarchy's"
grep -q "$OMARCHY_USER_PATH/default/bash/env-bootstrap" "$HOME/.bashrc" && ok "~/.bashrc sources the userland bootstrap" || bad "~/.bashrc bootstrap path"
[[ -n $(ls "$HOME/.local/state/omarchy/migrations" 2>/dev/null) ]] && ok "migrations marked done" || bad "migrations not marked"
t=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null); [[ -n $t && -d $HOME/.local/state/omarchy/current/theme ]] && ok "theme: $t" || bad "no current theme"
if [[ $(target_dm running) == sddm ]]; then
  sudo grep -q '^Session=/usr/share/wayland-sessions/omarchy.desktop' /var/lib/sddm/state.conf 2>/dev/null && ok "SDDM default session" || bad "SDDM default session not set"
  sudo grep -qx "User=$USER" /var/lib/sddm/state.conf 2>/dev/null && ok "SDDM remembers $USER (greeter has no user field)" || bad "SDDM last user not $USER: the greeter would log in with an empty name"
  if [[ -e /var/lib/omageeko/greeter-hold ]]; then ok "greeter held until the install finishes (sles/install.sh)"
  elif seat0_user_session; then ok "greeter: $USER is logged in on seat0"
  elif greeter_stale; then bad "greeter started before state.conf was written: it would log in with an empty name (sudo systemctl restart sddm)"
  elif [[ -n $(greeter_pid) ]]; then ok "greeter running with the current remembered user"
  else bad "no greeter running and nobody logged in on seat0"; fi
fi
for f in hypr/bindings.lua hypr/input.lua omarchy/shell.json; do
  cmp -s "$OMAGEEKO_SLES/hosts/${OMAGEEKO_HOST_PROFILE:-kvm-guest}/home/.config/$f" "$HOME/.config/$f" && ok "host profile: $f" || bad "host profile file differs: $f"
done
tf="$OMAGEEKO_SLES/hosts/${OMAGEEKO_HOST_PROFILE:-kvm-guest}/theme"
[[ ! -f $tf || $(tr -d '[:space:]' < "$tf") == "$(cat "$HOME/.local/state/omarchy/current/theme.name")" ]] && ok "host profile theme" || bad "theme differs from host profile"
grep -qs 'org\.gnome\.Nautilus' "$HOME/.config/mimeapps.list" "$HOME/.config/omarchy/shell.json" && bad "Nautilus still referenced in mimeapps/shell.json" || ok "Files (folio) is the file manager in mimeapps/dock"
[[ $(xdg-mime query default inode/directory 2>/dev/null) == folio.desktop ]] && ok "inode/directory -> folio.desktop" || bad "inode/directory default: $(xdg-mime query default inode/directory 2>/dev/null)"
tm="$OMAGEEKO_SLES/hosts/${OMAGEEKO_HOST_PROFILE:-kvm-guest}/terminal"
if [[ -f $tm ]]; then
  id=$("$HOME/.local/bin/xdg-terminal-exec" --print-id 2>/dev/null)
  [[ $id == *"$(tr -d '[:space:]' < "$tm")"* ]] && ok "default terminal: $id" || bad "default terminal is '${id:-none}', host profile wants $(cat "$tm")"
fi
bf="$OMAGEEKO_SLES/hosts/${OMAGEEKO_HOST_PROFILE:-kvm-guest}/browser"
if [[ -f $bf ]]; then
  case $(tr -d '[:space:]' < "$bf") in brave) want=brave-browser.desktop ;; chromium) want=chromium.desktop ;; *) want=? ;; esac
  for scheme in http https; do
    got=$(xdg-mime query default x-scheme-handler/$scheme 2>/dev/null)
    [[ $got == "$want" ]] && ok "default browser for $scheme: $got" || bad "default browser for $scheme is '${got:-none}', host profile wants $want"
  done
  # what Super+Shift+B and web apps use: Omarchy's own lookup, in the session's PATH
  got=$(PATH="$OMARCHY_USER_PATH/bin:$HOME/.local/bin:$PATH" XDG_CURRENT_DESKTOP=Hyprland omarchy-cmd-default-browser 2>/dev/null)
  [[ $got == "$want" || $got == omarchy-browser.desktop ]] && ok "omarchy-cmd-default-browser: $got" || bad "omarchy-cmd-default-browser: '${got:-nothing}' (Super+Shift+B would do nothing)"
fi
# SELinux labels: $HOME must stay user_home_dir_t, ~/.ssh ssh_home_t, and nothing may
# carry a /tmp label from a staging dir (breaks sshd and logins)
[[ $(stat -c %C "$HOME") == *:user_home_dir_t:* ]] && ok "\$HOME label user_home_dir_t" || bad "\$HOME label: $(stat -c %C "$HOME")"
[[ ! -d $HOME/.ssh || $(stat -c %C "$HOME/.ssh") == *:ssh_home_t:* ]] && ok "~/.ssh label" || bad "~/.ssh label: $(stat -c %C "$HOME/.ssh")"
n=$(find "$HOME" -xdev -context '*_tmp_t:*' 2>/dev/null | wc -l)
(( n == 0 )) && ok "no /tmp labels under \$HOME" || bad "$n paths under \$HOME carry a *_tmp_t label (sudo restorecon -R \$HOME)"
exit $fail
