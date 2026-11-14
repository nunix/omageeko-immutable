#!/bin/bash
# SLES layer 01b - Hyprland stack
# Rebuilds openSUSE's Hyprland packaging (pinned in hyprland.lock) for SLES 16.1
# in the shared SLES builder container (sles/builder), publishes it to the local
# repo and installs it in ONE transactional-update snapshot (active after reboot).
#
# Also the update path: after bump.sh moves the pins, rerun this. Only packages
# whose pin/patches changed are rebuilt, plus everything after them in
# hyprland.lock (ABI cascade). Nothing changed -> no build, no snapshot.
#
# Usage: install.sh [--check | --build-only] [--phase system|user|all]  (user = nothing to do)
#   --check       only report BuildRequires SLES can't satisfy (no build, no install)
#   --build-only  build and publish, don't create a snapshot
# Env:   OMAGEEKO_REBUILD=all | "name1 name2"   force rebuilds
#        OMAGEEKO_REBUILD_IMAGE=1               force a new builder image

source "$(dirname "$(readlink -f "$0")")/../../lib/common.sh"

LAYER_DIR="$OMAGEEKO_SLES/layers/01b-hyprland"
# What Omarchy (install/omarchy-base.packages) needs; libraries come as dependencies
INSTALL=(hyprland hyprland-guiutils hyprpicker hyprsunset xdg-desktop-portal-hyprland uwsm)

parse_phase "$@"
[[ $PHASE == user ]] && { log "Layer 01b has no user part"; exit 0; }
mode=install
case "${ARGS[0]:-}" in
  --check) mode=check ;;
  --build-only) mode=build ;;
  "") ;;
  *) die "Unknown option: ${ARGS[0]}" ;;
esac

require_sles_immutable
ensure_local_repo
ensure_builder

if [[ $mode == check ]]; then
  build_lock 01b "$LAYER_DIR" "$LAYER_DIR/hyprland.lock" check
  exit
fi
build_lock 01b "$LAYER_DIR" "$LAYER_DIR/hyprland.lock"
[[ $mode == build ]] && exit 0

install_from_repo 01b "${INSTALL[@]}"
finish_layer sles/layers/01b-hyprland/verify.sh
