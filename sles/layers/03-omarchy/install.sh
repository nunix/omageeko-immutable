#!/bin/bash
# SLES layer 03 - Omarchy core (option B: userland)
# Builds the omageeko RPMs in the SLES builder and unpacks them for this user:
#   ~/.local/share/omarchy    OMARCHY_PATH: commands (bin/), shell, themes, defaults
#   ~/.local/share/omageeko   omageeko data + the rewritten skel for layer 04
#   ~/.config/...             user units, uwsm env.d, mise conf.d, fontconfig, xkb
#   ~/.local/share/...        fonts, icons, mimeapps, terminal order
# Packaged paths (/usr/share/omarchy, /usr/bin/omarchy-*) are rewritten to the
# userland tree. Updating Omarchy = rerun: no snapshot, no reboot.
# Host: only omageeko-sles (session entry + lock-screen PAM), plus omageeko-sles-sddm
# (Omarchy's Wayland greeter config + theme) when SDDM is the display manager.
# Usage: install.sh [--phase system|user|all]  (system = builds + omageeko-sles,
#        user = deploy the tree and Ghostty from the built RPMs)
# Not shipped on purpose: upstream's sudoers rules (they would grant root to
# scripts in a user-writable directory).

source "$(dirname "$(readlink -f "$0")")/../../lib/common.sh"
source "$OMAGEEKO_SLES/lib/userland.sh"

LAYER_DIR="$OMAGEEKO_SLES/layers/03-omarchy"

parse_phase "$@"

require_sles_immutable
ensure_local_repo
ensure_builder
ensure_repo_registered

# ---- system: builds + the host package (session entry + lock PAM)
if [[ $PHASE != user ]]; then
  # Spec inputs (commit from upstream.lock, pkgmap.tsv), as on Tumbleweed
  bash "$OMAGEEKO_ROOT/packages/omageeko/prepare.sh"
  build_lock 03 "$LAYER_DIR" "$LAYER_DIR/build.lock"
  # SDDM (layer 00): Omarchy's greeter config + theme come with omageeko-sles-sddm
  if [[ $(target_dm) == sddm ]]; then
    install_from_repo 03 omageeko-sles omageeko-sles-sddm
  else
    install_from_repo 03 omageeko-sles
  fi
  [[ $PHASE == system ]] && { finish_layer "sles/layers/03-omarchy/install.sh --phase user"; exit 0; }
fi

# ---- userland tree
stamp=$( (for p in omageeko omageeko-settings omageeko-session jetbrains-mono-nerd-fonts ia-writer-fonts; do
  basename "$(local_rpm "$p")"; done
  (cd "$OMAGEEKO_SLES" && find overlay lib/userland.sh -type f -print0 | sort -z | xargs -0 sha256sum)
  ) | sha256sum | cut -d' ' -f1)
if [[ -x $OMARCHY_USER_PATH/bin/omarchy-version && $(cat "$STAMP_DIR/03-userland" 2>/dev/null) == "$stamp" &&
      ${OMAGEEKO_REDEPLOY:-} != 1 ]]; then
  log "Userland Omarchy tree already matches the built RPMs (OMAGEEKO_REDEPLOY=1 to redo)"
else
  stage=$(mktemp -d)
  rpm_payload "$stage" "$(local_rpm omageeko)" "$(local_rpm omageeko-settings)" "$(local_rpm omageeko-session)" \
    "$(local_rpm jetbrains-mono-nerd-fonts)" "$(local_rpm ia-writer-fonts)"
  log "Deploying Omarchy to $OMARCHY_USER_PATH"
  deploy_omarchy_tree "$stage"
  deploy_user_integration "$stage"
  rm -rf "$stage"
  echo "$stamp" > "$STAMP_DIR/03-userland"
  log "Omarchy $(cat "$OMARCHY_USER_PATH/version") (omageeko $(cut -c1-12 "$OMAGEEKO_USER_DATA/upstream-commit")) deployed"
fi

# ---- Ghostty bundle (default terminal)
ghostty_rpm=$(local_rpm ghostty)
if [[ -x $GHOSTTY_HOME/bin/ghostty && $(cat "$STAMP_DIR/03-ghostty-deployed" 2>/dev/null) == "$(basename "$ghostty_rpm")" &&
      ${OMAGEEKO_REDEPLOY:-} != 1 ]]; then
  log "Ghostty bundle already matches $(basename "$ghostty_rpm")"
else
  log "Deploying Ghostty to $GHOSTTY_HOME"
  deploy_ghostty "$ghostty_rpm"
  basename "$ghostty_rpm" > "$STAMP_DIR/03-ghostty-deployed"
  log "$("$GHOSTTY_HOME/bin/ghostty" --version 2>/dev/null | head -1)"
fi

finish_layer sles/layers/03-omarchy/verify.sh
