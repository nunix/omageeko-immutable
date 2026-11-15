# Userland deployment helpers for the SLES target (layer 03 option B).
# Source after common.sh. Nothing here writes outside $HOME except through the
# builder container (which only writes into the given output directory).

OMARCHY_USER_PATH="$HOME/.local/share/omarchy"
OMAGEEKO_USER_DATA="$HOME/.local/share/omageeko"

# rpm_payload <outdir> <rpm>... : unpack RPM payloads into <outdir> (no install)
# Stages live in /tmp: copies out of them use --no-preserve=context,xattr (context alone still copies the label xattr), or their
# *_tmp_t labels end up on files (and, through layer 04, on $HOME itself).
rpm_payload() {
  local out="$1"; shift
  mkdir -p "$out"
  local args=() r
  for r in "$@"; do args+=("/rpms/$(basename "$r")"); done
  # All RPMs must sit in one directory (the local repo arch dirs are merged via a temp dir)
  local tmp; tmp=$(mktemp -d)
  cp -f "$@" "$tmp/"
  podman run --rm --security-opt label=disable -v "$tmp:/rpms:ro" -v "$out:/out" \
    "$BUILDER_IMAGE" bash -c 'cd /out && for r in "$@"; do rpm2cpio "$r" | cpio -idm --quiet; done' _ "${args[@]}"
  rm -rf "$tmp"
}

# sles_payload <outdir> <package>... : download SLES/Package Hub packages in the
# builder and unpack them into <outdir>. For data (fonts, themes) that needs no
# host install.
sles_payload() {
  local out="$1"; shift
  mkdir -p "$out"
  podman run --rm --security-opt label=disable "${SCC_RUN_ARGS[@]}" -v "$out:/out" \
    -v "$BUILDER_CACHE_VOLUME:/var/cache/zypp" "$BUILDER_IMAGE" bash -c '
      set -e
      zypper --non-interactive --quiet --gpg-auto-import-keys refresh >/dev/null || true
      d=$(mktemp -d)
      zypper --non-interactive --quiet --pkg-cache-dir "$d" download "$@" >/dev/null
      cd /out
      find "$d" -name "*.rpm" -print0 | while IFS= read -r -d "" r; do rpm2cpio "$r" | cpio -idm --quiet; done' _ "$@"
}

# apply_patch <dir> <strip> <patchfile> : patch -p<strip> --fuzz=0 in the builder
# (the SLES host has no `patch`, and doesn't need one)
apply_patch() {
  podman run --rm --security-opt label=disable -v "$1:/work" -v "$3:/p.patch:ro" \
    "$BUILDER_IMAGE" patch -d /work -p"$2" --fuzz=0 --no-backup-if-mismatch --quiet -i /p.patch
}

# local_rpm <name> : newest RPM file for <name> in the local repo
local_rpm() {
  local f best=""
  for f in "$OMAGEEKO_REPO_DIR"/{noarch,x86_64}/"$1"-[0-9]*.rpm; do
    [[ -e $f ]] || continue
    [[ $(rpm -qp --qf '%{NAME}' "$f" 2>/dev/null) == "$1" ]] && best=$f
  done
  [[ -n $best ]] || die "No $1 RPM in $OMAGEEKO_REPO_DIR"
  echo "$best"
}

# adapt_agent_skills <skills-dir>: the omageeko skill (from the omageeko RPM) is written for
# Tumbleweed, where omageeko lives in system paths. rewrite_paths already points /usr/share/omarchy
# and /usr/share/omageeko at the userland tree; here the files layer 03 deploys to user config
# instead of /etc and /usr/share/uwsm (deploy_user_integration) get their userland path too, and the
# skill says that sles-atomic wins on this system. System paths of host RPMs (omageeko-hardware:
# /usr/libexec/omageeko, wireplumber labels) and /var/lib/omageeko stay: they're real here.
adapt_agent_skills() {
  local dir="$1" cfg="${XDG_CONFIG_HOME:-$HOME/.config}" f
  [[ -d $dir/omageeko ]] || return 0
  grep -rlIE '/usr/share/uwsm/env\.d|/etc/mise/conf\.d|/(usr/lib|etc)/systemd/user' "$dir/omageeko" 2>/dev/null |
    xargs -r sed -i -E \
      -e "s#/usr/share/uwsm/env\.d#$cfg/uwsm/env.d#g" \
      -e "s#/etc/mise/conf\.d#$cfg/mise/conf.d#g" \
      -e "s#/(usr/lib|etc)/systemd/user#$cfg/systemd/user#g"
  f="$dir/omageeko/SKILL.md"
  if [[ -f $f ]] && ! grep -q 'omageeko-sles:' "$f"; then
    # after the front matter (second "---" line)
    awk 'BEGIN{n=0} {print} /^---$/ && ++n==2 {print ""; print "> omageeko-sles: on this machine (SLES 16.1 Immutable, omageeko-immutable) this skill is"; print "> background about the Tumbleweed sibling. Paths below point at the userland tree. The"; print "> **sles-atomic** skill wins wherever they disagree: no zypper on the host, no vendor repos on"; print "> the host, updates through transactional-update and the SLES layers."}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  fi
}

# rewrite_paths <dir|file>... : point packaged paths at the userland tree.
#   /usr/share/omarchy (not omarchy-platform) -> ~/.local/share/omarchy
#   /usr/share/omageeko                       -> ~/.local/share/omageeko
#   /usr/bin/omarchy-* /usr/bin/omageeko-*    -> ~/.local/share/omarchy/bin/...
rewrite_paths() {
  local files
  files=$(grep -rlIE '/usr/share/(omarchy|omageeko)|/usr/bin/om(archy|ageeko)-' "$@" 2>/dev/null || true)
  [[ -n $files ]] || return 0
  # shellcheck disable=SC2086
  sed -i -E \
    -e "s#/usr/bin/(omarchy|omageeko)-#$OMARCHY_USER_PATH/bin/\1-#g" \
    -e "s#/usr/share/omageeko([^-[:alnum:]_]|\$)#$OMAGEEKO_USER_DATA\1#g" \
    -e "s#/usr/share/omarchy([^-[:alnum:]_]|\$)#$OMARCHY_USER_PATH\1#g" \
    $files
}

# deploy_omarchy_tree <stage> : stage = unpacked omageeko + omageeko-settings + omageeko-session
# Builds the new tree next to the old one and swaps it in.
deploy_omarchy_tree() {
  local stage="$1" new="$OMARCHY_USER_PATH.new" old="$OMARCHY_USER_PATH.old"
  rm -rf "$new" "$old"
  cp -a --no-preserve=context,xattr "$stage/usr/share/omarchy" "$new"
  # Packaged bin/ holds symlinks to /usr/bin; userland needs the real scripts, since
  # omarchy-security-functions trusts only $OMARCHY_PATH/bin/<cmd> outside /usr/bin
  find "$new/bin" -maxdepth 1 -type l -delete
  cp -a --no-preserve=context,xattr "$stage"/usr/bin/omarchy-* "$stage"/usr/bin/omageeko-* "$new/bin/"
  # Backports from upstream edge (sles/overlay/patches): tree-* on the tree,
  # config-* on its config/ (skel/.config gets them below)
  local p
  for p in "$OMAGEEKO_SLES"/overlay/patches/tree-*.patch "$OMAGEEKO_SLES"/overlay/patches/config-*.patch; do
    [[ -e $p ]] || continue
    apply_patch "$new" 1 "$p" || die "Backport $(basename "$p") no longer applies"
  done
  chmod 755 "$new"/bin/*
  # SLES Immutable replacements and additions (package management, updates)
  cp -a --no-preserve=context,xattr "$OMAGEEKO_SLES"/overlay/bin/. "$new/bin/"
  rewrite_paths "$new"
  # env-bootstrap prepends $OMARCHY_PATH/bin only in dev-link mode; userland always needs it
  sed -i -E 's#^if \[ "\$OMARCHY_PATH" != [^]]+ \]; then$#if [ -n "$OMARCHY_PATH" ]; then  \# omageeko-sles: commands live in $OMARCHY_PATH/bin, not /usr/bin#' \
    "$new/default/bash/env-bootstrap"
  grep -q 'omageeko-sles: commands live' "$new/default/bash/env-bootstrap" ||
    die "env-bootstrap layout changed upstream; update deploy_omarchy_tree"

  rm -rf "$OMAGEEKO_USER_DATA.new"
  cp -a --no-preserve=context,xattr "$stage/usr/share/omageeko" "$OMAGEEKO_USER_DATA.new"
  cp -a --no-preserve=context,xattr "$OMAGEEKO_SLES"/overlay/share/. "$OMAGEEKO_USER_DATA.new/"
  # skel (rewritten) for layer 04's user reset
  cp -a --no-preserve=context,xattr "$stage/etc/skel" "$OMAGEEKO_USER_DATA.new/skel"
  for p in "$OMAGEEKO_SLES"/overlay/patches/config-*.patch; do
    [[ -e $p ]] || continue
    apply_patch "$OMAGEEKO_USER_DATA.new/skel/.config" 2 "$p" ||
      die "Backport $(basename "$p") no longer applies to skel"
  done
  rewrite_paths "$OMAGEEKO_USER_DATA.new"
  adapt_agent_skills "$OMAGEEKO_USER_DATA.new/agents/skills"

  [[ -d $OMARCHY_USER_PATH ]] && mv "$OMARCHY_USER_PATH" "$old"
  mv "$new" "$OMARCHY_USER_PATH"
  rm -rf "$old" "$OMAGEEKO_USER_DATA.old"
  [[ -d $OMAGEEKO_USER_DATA ]] && mv "$OMAGEEKO_USER_DATA" "$OMAGEEKO_USER_DATA.old"
  mv "$OMAGEEKO_USER_DATA.new" "$OMAGEEKO_USER_DATA"
  rm -rf "$OMAGEEKO_USER_DATA.old"
}

# deploy_user_integration <stage> : the /usr and /etc bits omageeko RPMs ship,
# mapped to their XDG user locations
deploy_user_integration() {
  local stage="$1" f
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}" data="${XDG_DATA_HOME:-$HOME/.local/share}"

  # Fonts, icons
  mkdir -p "$data/fonts" "$data/icons"
  for f in "$stage"/usr/share/fonts/*; do
    [[ -d $f ]] && cp -a --no-preserve=context,xattr "$f" "$data/fonts/"
  done
  [[ -d $stage/usr/share/icons/hicolor ]] && cp -a --no-preserve=context,xattr "$stage/usr/share/icons/hicolor" "$data/icons/"

  # Default applications and terminal preference
  # From the (backport-patched) tree, which is what the RPM installs too
  install -Dm644 "$OMARCHY_USER_PATH/default/applications/mimeapps.list" "$data/applications/mimeapps.list"
  install -Dm644 "$stage/usr/share/xdg-terminal-exec/hyprland-xdg-terminals.list" \
    "$data/xdg-terminal-exec/hyprland-xdg-terminals.list"

  # systemd user units (and the keep-shell drop-in for the uwsm-managed compositor)
  mkdir -p "$cfg/systemd/user"
  cp -a --no-preserve=context,xattr "$stage"/usr/lib/systemd/user/. "$cfg/systemd/user/"
  cp -a --no-preserve=context,xattr "$stage"/etc/systemd/user/. "$cfg/systemd/user/"
  rewrite_paths "$cfg/systemd/user"

  # Session environment: uwsm reads env.d from $XDG_CONFIG_HOME as well
  mkdir -p "$cfg/uwsm/env.d"
  cp -a --no-preserve=context,xattr "$stage"/usr/share/uwsm/env.d/. "$cfg/uwsm/env.d/"
  rewrite_paths "$cfg/uwsm/env.d"

  # /etc defaults with user-level equivalents
  mkdir -p "$cfg/mise/conf.d" "$cfg/fontconfig/conf.d" "$cfg/xkb"
  cp -a --no-preserve=context,xattr "$stage"/etc/mise/conf.d/. "$cfg/mise/conf.d/"
  install -Dm644 "$stage/usr/share/fontconfig/conf.avail/50-omarchy.conf" "$cfg/fontconfig/conf.d/50-omarchy.conf"
  cp -a --no-preserve=context,xattr "$stage"/etc/xkb/. "$cfg/xkb/"
  [[ -f $cfg/fastfetch/config.jsonc ]] || install -Dm644 "$stage/etc/fastfetch/config.jsonc" "$cfg/fastfetch/config.jsonc"
  rewrite_paths "$cfg/mise/conf.d" "$cfg/fastfetch"

  systemctl --user daemon-reload 2>/dev/null || true
  fc-cache -f >/dev/null 2>&1 || true
}

# deploy_ghostty <ghostty-rpm> : Ghostty as a self-contained userland bundle in
# ~/.local/opt/ghostty. The RPM is built from upstream with vendored, statically
# linked dependencies; libadwaita (absent on the SLES host) is bundled in lib/ and
# found through an RPATH ($ORIGIN/../lib), so nothing leaks into the shells
# Ghostty starts (no LD_LIBRARY_PATH).
GHOSTTY_HOME="$HOME/.local/opt/ghostty"
deploy_ghostty() {
  local rpm="$1" stage new="$GHOSTTY_HOME.new" f
  local data="${XDG_DATA_HOME:-$HOME/.local/share}" cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
  stage=$(mktemp -d)
  rpm_payload "$stage" "$rpm"
  rm -rf "$new"
  mkdir -p "$new"
  cp -a --no-preserve=context,xattr "$stage/usr/." "$new/"
  # libadwaita from SLES (data-only unpack, no host install) + RPATH in the builder
  sles_payload "$stage/adw" libadwaita-1-0
  mkdir -p "$new/lib"
  cp -a --no-preserve=context,xattr "$stage"/adw/usr/lib64/libadwaita-1.so.0* "$new/lib/"
  podman run --rm --security-opt label=disable "${SCC_RUN_ARGS[@]}" -v "$new:/g" \
    -v "$BUILDER_CACHE_VOLUME:/var/cache/zypp" "$BUILDER_IMAGE" bash -c '
      zypper --non-interactive --quiet --gpg-auto-import-keys refresh >/dev/null 2>&1 || true
      zypper --non-interactive --quiet install --no-recommends patchelf >/dev/null
      patchelf --set-rpath "\$ORIGIN/../lib" /g/bin/ghostty'
  rm -rf "$stage"
  rm -rf "$GHOSTTY_HOME.old"
  [[ -d $GHOSTTY_HOME ]] && mv "$GHOSTTY_HOME" "$GHOSTTY_HOME.old"
  mv "$new" "$GHOSTTY_HOME"
  rm -rf "$GHOSTTY_HOME.old"

  # Command, desktop entry, D-Bus activation, systemd user unit, icons, terminfo
  mkdir -p "$HOME/.local/bin" "$data/applications" "$data/dbus-1/services" "$cfg/systemd/user" "$data/icons" "$HOME/.terminfo"
  ln -sfn "$GHOSTTY_HOME/bin/ghostty" "$HOME/.local/bin/ghostty"
  for f in "$GHOSTTY_HOME"/share/applications/*.desktop; do
    [[ -e $f ]] && sed "s#/usr/bin/ghostty#$GHOSTTY_HOME/bin/ghostty#g; s#^Exec=ghostty#Exec=$GHOSTTY_HOME/bin/ghostty#; s#^TryExec=ghostty#TryExec=$GHOSTTY_HOME/bin/ghostty#" "$f" > "$data/applications/$(basename "$f")"
  done
  for f in "$GHOSTTY_HOME"/share/dbus-1/services/*.service; do
    [[ -e $f ]] && sed "s#/usr/bin/ghostty#$GHOSTTY_HOME/bin/ghostty#g" "$f" > "$data/dbus-1/services/$(basename "$f")"
  done
  for f in "$GHOSTTY_HOME"/share/systemd/user/*.service "$GHOSTTY_HOME"/lib/systemd/user/*.service; do
    [[ -e $f ]] && sed "s#/usr/bin/ghostty#$GHOSTTY_HOME/bin/ghostty#g" "$f" > "$cfg/systemd/user/$(basename "$f")"
  done
  [[ -d $GHOSTTY_HOME/share/icons/hicolor ]] && cp -a --no-preserve=context,xattr "$GHOSTTY_HOME/share/icons/hicolor" "$data/icons/"
  [[ -d $GHOSTTY_HOME/share/terminfo ]] && cp -a --no-preserve=context,xattr "$GHOSTTY_HOME"/share/terminfo/. "$HOME/.terminfo/"
  systemctl --user daemon-reload 2>/dev/null || true
  update-desktop-database "$data/applications" 2>/dev/null || true
}
