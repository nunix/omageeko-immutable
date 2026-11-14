#!/bin/bash
# SLES layer 02 - build RPMs
# Desktop-critical software SLES doesn't ship (quickshell, owe/owe-lockfeed, the
# titlebars plugin, the screen-share picker, ttfx), built in the shared SLES
# builder from omageeko's own specs (packages/<name>), plus the two pool packages
# SLES lacks to build them. Installed in one transactional-update snapshot.
# Fonts and the Omarchy tree are NOT here: layer 03 puts them in userland.
#
# Usage: install.sh [--check | --build-only] [--phase system|user|all]  (user = nothing to do)
# Env:   OMAGEEKO_REBUILD=all | "name1 name2"

source "$(dirname "$(readlink -f "$0")")/../../lib/common.sh"

LAYER_DIR="$OMAGEEKO_SLES/layers/02-build-rpms"
INSTALL=(quickshell owe owe-lockfeed omarchy-hyprland-titlebars hyprland-preview-share-picker ttfx folio)

parse_phase "$@"
[[ $PHASE == user ]] && { log "Layer 02 has no user part"; exit 0; }
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
# hyprland-devel etc. come from layer 01b through the local repo
[[ -f $OMAGEEKO_REPO_DIR/repodata/repomd.xml ]] || die "Run layer 01b first"
ensure_repo_registered

if [[ $mode == check ]]; then
  build_lock 02 "$LAYER_DIR" "$LAYER_DIR/build.lock" check
  exit
fi
build_lock 02 "$LAYER_DIR" "$LAYER_DIR/build.lock"
[[ $mode == build ]] && exit 0

install_from_repo 02 "${INSTALL[@]}"
finish_layer sles/layers/02-build-rpms/verify.sh
