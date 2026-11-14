#!/bin/bash
# SLES layer 00 - verify bootstrap
source "$(dirname "$(readlink -f "$0")")/../../lib/common.sh"
set +e
fail=0; ok() { printf '  \e[32mok\e[0m   %s\n' "$1"; }; bad() { printf '  \e[31mFAIL\e[0m %s\n' "$1"; fail=1; }
LAYER_DIR="$OMAGEEKO_SLES/layers/00-bootstrap"
reboot_pending && bad "a newer snapshot is waiting for a reboot"
n=0
while read -r p; do
  rpm -q --whatprovides "$p" &>/dev/null && n=$((n+1)) || bad "host package missing: $p"
done < <(grep -vE '^[[:space:]]*(#|$)' "$LAYER_DIR/host.packages")
ok "$n host packages present"
[[ $(systemctl get-default) == graphical.target ]] && ok "default target: graphical" || bad "default target: $(systemctl get-default)"
dm=$(target_dm running)
[[ $dm != none ]] && ok "display manager: $dm" || bad "no display-manager.service"
if [[ $dm == sddm ]]; then
  [[ $(sudo readlink /etc/systemd/system/display-manager.service) == */sddm.service ]] &&
    ok "display-manager.service is sddm.service (Conflicts=getty@tty1)" ||
    bad "display-manager.service is $(sudo readlink /etc/systemd/system/display-manager.service): getty@tty1 kills the greeter on VT1; rerun layer 00"
  [[ $(stat -c %C /usr/bin/sddm 2>/dev/null) == *:xdm_exec_t:* ]] && ok "sddm labelled xdm_exec_t (SELinux)" || bad "sddm label: $(stat -c %C /usr/bin/sddm)"
fi
grep -qx 'strategy=off' /etc/rebootmgr.conf 2>/dev/null && ok "rebootmgr strategy off" || bad "rebootmgr strategy not off"
for u in pipewire.service wireplumber.service pipewire-pulse.socket; do
  [[ -n $(systemctl --user list-unit-files "$u" --no-legend 2>/dev/null) ]] && ok "user unit $u" || bad "user unit $u missing"
done
[[ -f /usr/share/xdg-desktop-portal/portals/gtk.portal ]] && ok "GTK portal" || bad "GTK portal missing"
exit $fail
