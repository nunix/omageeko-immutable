#!/bin/bash
# SLES layer 05 - hardware (bare metal)
# What omageeko's Tumbleweed layer 05 does, the immutable way:
#   system (one pending snapshot, stacked with layers 00-03):
#     - hosts/<profile>/host.packages (machine-specific: fingerprint, bolt, fwupd, ...)
#     - omageeko-hardware (built with omageeko in layer 03): UCM audio labels, display I2C
#       access for ddcutil, monitor wake kick, Bluetooth LE Device Privacy Mode helper
#     - bluez-tools (built in layer 02): bt-agent, the pairing agent Omarchy's
#       bt-agent.service runs; without it pairing loops
#     - power-profiles-daemon and omageeko-bt-device-privacy.{service,timer} enabled
#   user: omageeko-monitor-wake-kick.service when the host profile lists monitors
# Runs on bare metal, or in a VM when the profile has host.packages (rehearsal);
# otherwise it's a no-op. Firmware is already in a minimal SLES (kernel-firmware-all).
# Not here (manual, interactive): fingerprint enrollment (omarchy-setup-security-fingerprint).
# Usage: install.sh [--phase system|user|all]

source "$(dirname "$(readlink -f "$0")")/../../lib/common.sh"

LAYER_DIR="$OMAGEEKO_SLES/layers/05-hardware"
PROFILE="${OMAGEEKO_HOST_PROFILE:-kvm-guest}"
HOST_PACKAGES="$OMAGEEKO_SLES/hosts/$PROFILE/host.packages"
SYSTEM_UNITS=(power-profiles-daemon.service omageeko-bt-device-privacy.service omageeko-bt-device-privacy.timer)

parse_phase "$@"
require_sles_immutable

if systemd-detect-virt -q && [[ ! -f $HOST_PACKAGES ]]; then
  log "Virtual machine with profile $PROFILE: no hardware layer"
  exit 0
fi

if [[ $PHASE != user ]]; then
  if [[ -f $HOST_PACKAGES ]]; then
    mapfile -t pkgs < <(grep -vE '^[[:space:]]*(#|$)' "$HOST_PACKAGES")
    (( ${#pkgs[@]} )) && host_install "${pkgs[@]}"
  fi
  install_from_repo 05 omageeko-hardware bluez-tools
  root=$(target_root)
  todo=()
  for u in "${SYSTEM_UNITS[@]}"; do
    sudo systemctl --root="$root" is-enabled -q "$u" 2>/dev/null || todo+=("$u")
  done
  if (( ${#todo[@]} )); then
    log "Enabling ${todo[*]}"
    tu_run "systemctl enable ${todo[*]}"
  fi
  [[ $PHASE == system ]] && { finish_layer "sles/layers/05-hardware/install.sh --phase user"; exit 0; }
fi

# ---- user: Bluetooth pairing agent and monitor wake kick
systemctl --user daemon-reload
# Omarchy enables bt-agent.service at the first login (install/user/first-run); enable it now
# so pairing works from that login on and verify can check it
if systemctl --user cat bt-agent.service &>/dev/null && ! systemctl --user is-enabled -q bt-agent.service 2>/dev/null; then
  systemctl --user enable bt-agent.service
  log "Bluetooth pairing agent (bt-agent.service) enabled"
fi
# the host profile's monitor list arrives with layer 04
if [[ -f $HOME/.config/omageeko/monitor-wake-kick ]]; then
  if ! systemctl --user is-enabled -q omageeko-monitor-wake-kick.service 2>/dev/null; then
    systemctl --user enable omageeko-monitor-wake-kick.service
    log "Monitor wake kick enabled for: $(grep -vE '^[[:space:]]*(#|$)' "$HOME/.config/omageeko/monitor-wake-kick" | tr '\n' ' ')"
  fi
fi

finish_layer sles/layers/05-hardware/verify.sh
