#!/bin/bash
# SLES layer 00 - bootstrap
# The desktop base a *minimal* SLES 16.1 Immutable install lacks (the KDE install
# brought it implicitly): audio, graphics, desktop services, XDG plumbing, icons,
# fonts, Flatpak, commands Omarchy scripts call (host.packages). Plus:
#   - graphical.target as the default target
#   - SDDM as display manager (decision D-1, like upstream Omarchy); its Omarchy
#     config and theme come with omageeko-sles-sddm (layer 03). Only when the next
#     boot has no display manager or already uses SDDM; OMAGEEKO_DM=sddm forces it.
#   - rebootmgr strategy off (decision D-3: omageeko-update handles updates/reboots)
# Everything goes into the pending snapshot shared with layers 01-03; nothing
# changes when the next boot already matches.
#
# Usage: install.sh [--phase system|user|all]   (user = nothing to do)

source "$(dirname "$(readlink -f "$0")")/../../lib/common.sh"

LAYER_DIR="$OMAGEEKO_SLES/layers/00-bootstrap"
list() { grep -vE '^[[:space:]]*(#|$)' "$1"; }
parse_phase "$@"
[[ $PHASE == user ]] && { log "Layer 00 has no user part"; exit 0; }

require_sles_immutable

mapfile -t host < <(list "$LAYER_DIR/host.packages")
host_install "${host[@]}"

root=$(target_root)
sudo_cat() { sudo cat "$1" 2>/dev/null || true; }

# ---- display manager: SDDM (decision D-1, as upstream Omarchy). Its Omarchy
# config + theme (Wayland greeter in Hyprland) is omageeko-sles-sddm, installed
# by layer 03 once built. A host with another display manager keeps it.
dm=$(target_dm)
use_sddm=0
if [[ ${OMAGEEKO_DM:-} == sddm || $dm == none || $dm == sddm ]]; then
  use_sddm=1
else
  log "Display manager already set ($dm); keeping it (OMAGEEKO_DM=sddm to replace it)"
fi
(( use_sddm )) && host_install sddm-qt6
root=$(target_root)

changes=()
script=""
# sddm.service itself, not SUSE's display-manager-legacy wrapper: xdm's %post (pulled in
# by sddm-qt6) points display-manager.service at the wrapper, which only conflicts with
# getty@tty7. SDDM takes VT1, so getty@tty1 starts at the end of boot, hangs up VT1 and
# kills the greeter (SIGHUP). sddm.service has Conflicts=getty@tty1.
if (( use_sddm )) && [[ $(sudo readlink "$root/etc/systemd/system/display-manager.service" 2>/dev/null) != */sddm.service ]]; then
  changes+=("sddm as display-manager.service")
  script+="rm -f /etc/systemd/system/display-manager.service
systemctl enable sddm.service
"
fi
if [[ $(sudo readlink "$root/etc/systemd/system/default.target" 2>/dev/null) != */graphical.target ]]; then
  changes+=("graphical.target")
  script+="systemctl set-default graphical.target
"
fi
want_rbm=$'[rebootmgr]\nstrategy=off'
if [[ $(sudo_cat "$root/etc/rebootmgr.conf") != "$want_rbm" ]]; then
  changes+=("rebootmgr strategy off")
  script+="printf '%s\n' '[rebootmgr]' 'strategy=off' > /etc/rebootmgr.conf
"
fi

if (( ${#changes[@]} )); then
  log "System configuration: ${changes[*]}"
  tu_run "$script"
else
  log "System configuration already in place"
fi

finish_layer sles/layers/00-bootstrap/verify.sh
