#!/bin/bash
# SLES layer 01 - base
# Host:     the few packages the desktop core needs outside a user shell
#           (host.packages), one snapshot, only what the next boot lacks.
# Usage:    install.sh [--phase system|user|all]   (system = host part, user = the rest)
# Userland: mise in ~/.local/bin with Omarchy's base CLI/TUI set (mise-tools.toml),
#           fonts unpacked into ~/.local/share (user-data.packages).

source "$(dirname "$(readlink -f "$0")")/../../lib/common.sh"
source "$OMAGEEKO_SLES/lib/userland.sh"

LAYER_DIR="$OMAGEEKO_SLES/layers/01-base"
list() { grep -vE '^[[:space:]]*(#|$)' "$1"; }

parse_phase "$@"

require_sles_immutable

# ---- host
if [[ $PHASE != user ]]; then
  mapfile -t host < <(list "$LAYER_DIR/host.packages")
  host_install "${host[@]}"
  mapfile -t remove < <(list "$LAYER_DIR/host.remove")
  host_remove "${remove[@]}"
  [[ $PHASE == system ]] && { finish_layer "sles/layers/01-base/install.sh --phase user"; exit 0; }
fi

# ---- userland (needs flatpak from the host: on a minimal install, after the reboot)
command -v flatpak >/dev/null || die "flatpak missing on the host: run sles/layers/00-bootstrap and reboot"
ensure_local_repo
ensure_builder

# ---- xdg-terminal-exec (userland, pinned release, checksum-verified)
XTE_VERSION=0.14.4
XTE_SHA256=10e079032396a386dabcec5627893db17dc3c76c12318b3719d78f3b70aa7ef4
if ! grep -q "^# omageeko-sles: xdg-terminal-exec $XTE_VERSION\$" "$HOME/.local/bin/xdg-terminal-exec" 2>/dev/null; then
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/xte.tar.gz" "https://github.com/Vladimir-csp/xdg-terminal-exec/archive/refs/tags/v$XTE_VERSION.tar.gz"
  echo "$XTE_SHA256  $tmp/xte.tar.gz" | sha256sum -c --quiet - || { rm -rf "$tmp"; die "xdg-terminal-exec checksum mismatch"; }
  tar -xzf "$tmp/xte.tar.gz" -C "$tmp"
  # Version marker on line 2 (after the shebang) for the idempotency check above
  sed "1a # omageeko-sles: xdg-terminal-exec $XTE_VERSION" "$tmp/xdg-terminal-exec-$XTE_VERSION/xdg-terminal-exec" > "$tmp/xte"
  install -Dm755 "$tmp/xte" "$HOME/.local/bin/xdg-terminal-exec"
  rm -rf "$tmp"
  log "xdg-terminal-exec $XTE_VERSION in ~/.local/bin"
fi

# ---- mise (userland)
# Release binary from GitHub, checked against the release's SHASUMS256.txt
# (no piped installer). Later updates: `mise self-update`.
if [[ ! -x $HOME/.local/bin/mise ]]; then
  # (jq only arrives with this layer's snapshot, so parse with grep)
  tag=$(curl -fsSL https://api.github.com/repos/jdx/mise/releases/latest | grep -oE '"tag_name": *"v[^"]+"' | grep -oE 'v[0-9][^"]*')
  [[ $tag == v* ]] || die "Could not read the latest mise release"
  asset="mise-$tag-linux-x64"
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/$asset" "https://github.com/jdx/mise/releases/download/$tag/$asset"
  curl -fsSL -o "$tmp/SHASUMS256.txt" "https://github.com/jdx/mise/releases/download/$tag/SHASUMS256.txt"
  (cd "$tmp" && grep -E "[[:space:]]\.?/?$asset\$" SHASUMS256.txt | sha256sum -c --quiet -) ||
    { rm -rf "$tmp"; die "mise $tag checksum mismatch"; }
  install -Dm755 "$tmp/$asset" "$HOME/.local/bin/mise"
  rm -rf "$tmp"
  log "Installed mise $tag into ~/.local/bin"
fi
install -Dm644 "$LAYER_DIR/mise-tools.toml" "$HOME/.config/mise/conf.d/omageeko-sles-base.toml"
log "mise: installing the base CLI set"
"$HOME/.local/bin/mise" install --yes >/dev/null
"$HOME/.local/bin/mise" reshim

# ---- fonts and themes (userland)
mapfile -t data < <(list "$LAYER_DIR/user-data.packages")
stage=$(mktemp -d)
sles_payload "$stage" "${data[@]}"
mkdir -p "$HOME/.local/share/fonts" "$HOME/.local/share/themes" "$HOME/.local/share/icons"
[[ -d $stage/usr/share/fonts ]] && cp -a --no-preserve=context "$stage"/usr/share/fonts/. "$HOME/.local/share/fonts/"
[[ -d $stage/usr/share/themes ]] && cp -a --no-preserve=context "$stage"/usr/share/themes/. "$HOME/.local/share/themes/"
[[ -d $stage/usr/share/icons ]] && cp -a --no-preserve=context "$stage"/usr/share/icons/. "$HOME/.local/share/icons/"
rm -rf "$stage"
fc-cache -f >/dev/null 2>&1 || true
log "Fonts/themes in ~/.local/share: ${data[*]}"

# ---- Flathub apps (userland)
mapfile -t flatpaks < <(list "$LAYER_DIR/user-flatpaks")
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
for app in "${flatpaks[@]}"; do
  flatpak info --user "$app" &>/dev/null || { log "Flatpak: $app"; flatpak install --user --noninteractive flathub "$app" >/dev/null; }
done

# Chromium the way Omarchy calls it: a `chromium` command (web apps run the first
# word of chromium.desktop's Exec) and the chromium.desktop ID (default browser,
# mimeapps). Omarchy's flags file and its bundled extensions (in the userland
# tree) must be visible inside the sandbox.
if flatpak info --user org.chromium.Chromium &>/dev/null; then
  install -Dm755 /dev/stdin "$HOME/.local/bin/chromium" <<'SH'
#!/bin/sh
# omageeko-sles: Omarchy's `chromium` is the Flathub build
exec flatpak run --user org.chromium.Chromium "$@"
SH
  install -Dm644 /dev/stdin "$HOME/.local/share/applications/chromium.desktop" <<'DESKTOP'
[Desktop Entry]
# omageeko-sles: hidden alias so Omarchy's chromium.desktop ID reaches the Flathub Chromium
Type=Application
Name=Chromium
GenericName=Web Browser
Exec=chromium %U
Icon=org.chromium.Chromium
Terminal=false
NoDisplay=true
StartupWMClass=chromium
Categories=Network;WebBrowser;
MimeType=application/pdf;application/xhtml+xml;text/html;text/xml;image/webp;x-scheme-handler/http;x-scheme-handler/https;
DESKTOP
  mkdir -p "$HOME/.var/app/org.chromium.Chromium/config"
  ln -sfn "$HOME/.config/chromium-flags.conf" "$HOME/.var/app/org.chromium.Chromium/config/chromium-flags.conf"
  flatpak override --user --filesystem="$HOME/.local/share/omarchy:ro" --filesystem=xdg-config/chromium-flags.conf:ro org.chromium.Chromium
fi

finish_layer sles/layers/01-base/verify.sh
