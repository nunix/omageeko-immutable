#!/bin/bash
# SLES layer 04 - session (userland)
# Resets this user's dotfiles to Omarchy's defaults (the rewritten skel layer 03
# deployed to ~/.local/share/omageeko/skel), keeps a backup, marks the shipped
# migrations done, runs omarchy-provision-user, applies the host profile
# (sles/hosts/<profile>/home) and makes the Omarchy session SDDM's default.
# The user reset runs once; OMAGEEKO_RESET_USER=1 redoes it.
# ~/.claude* is never touched. No snapshot: everything here is in $HOME, except
# SDDM's remembered session in /var/lib/sddm (outside snapshots).
#
# Env: OMAGEEKO_HOST_PROFILE (default kvm-guest), OMAGEEKO_USER_NAME, OMAGEEKO_USER_EMAIL

source "$(dirname "$(readlink -f "$0")")/../../lib/common.sh"
source "$OMAGEEKO_SLES/lib/userland.sh"

STATE_DIR="$HOME/.local/state/omageeko"
SKEL="$OMAGEEKO_USER_DATA/skel"
PROFILE="${OMAGEEKO_HOST_PROFILE:-kvm-guest}"
PROFILE_DIR="$OMAGEEKO_SLES/hosts/$PROFILE/home"

parse_phase "$@"
[[ $PHASE == system ]] && { log "Layer 04 has no system part"; exit 0; }

require_sles_immutable
[[ -d $SKEL && -x $OMARCHY_USER_PATH/bin/omarchy-version ]] || die "Run sles/layers/03-omarchy first"
# Provisioning runs Omarchy scripts that need layer 01's host tools (jq, git, ...)
reboot_pending && die "A snapshot from layers 01-03 is waiting: reboot first, then rerun this layer"
command -v jq >/dev/null || die "jq missing: run sles/layers/01-base and reboot"
mkdir -p "$STATE_DIR/backups"

export OMARCHY_PATH="$OMARCHY_USER_PATH"
export PATH="$OMARCHY_PATH/bin:$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

if [[ ! -f $STATE_DIR/user-provisioned || ${OMAGEEKO_RESET_USER:-0} == 1 ]]; then
  OMARCHY_USER_NAME=${OMAGEEKO_USER_NAME:-$(git config --global user.name || true)}
  OMARCHY_USER_EMAIL=${OMAGEEKO_USER_EMAIL:-$(git config --global user.email || true)}
  : "${OMARCHY_USER_NAME:=$(getent passwd "$USER" | cut -d: -f5 | cut -d, -f1)}"
  export OMARCHY_USER_NAME OMARCHY_USER_EMAIL
  log "User identity: ${OMARCHY_USER_NAME:-?} <${OMARCHY_USER_EMAIL:-?}>"

  claude_sum=$(sha256sum ~/.claude/settings.json 2>/dev/null | cut -d' ' -f1 || true)

  # Backup once, before the very first reset (/home is not in root snapshots)
  if ! compgen -G "$STATE_DIR/backups/pre-04-*.tar.gz" >/dev/null; then
    backup="$STATE_DIR/backups/pre-04-$(date +%Y%m%d-%H%M%S).tar.gz"
    paths=()
    while IFS= read -r rel; do
      [[ -e $HOME/$rel ]] && paths+=("$rel")
    done < <(cd "$SKEL" && find . -mindepth 1 -maxdepth 2 \( -path ./.config -o -path ./.local -o -path ./.local/state -o -path ./.local/share \) -prune -o -print; \
             cd "$SKEL" && find .config .local/share .local/state -mindepth 1 -maxdepth 1 2>/dev/null)
    if (( ${#paths[@]} )); then
      tar -C "$HOME" -czf "$backup" "${paths[@]}"
      log "Backed up ${#paths[@]} existing dotfile paths to $backup"
    fi
  fi

  log "Copying Omarchy defaults from $SKEL"
  # Entries one by one: "cp -a SKEL/. HOME/" also gives $HOME the skel dir's mode,
  # owner and SELinux label. On the first minimal-VM run that put a /tmp label
  # on $HOME: sshd refused the key and logins failed.
  shopt -s dotglob nullglob
  for entry in "$SKEL"/*; do cp -af --no-preserve=context "$entry" "$HOME/"; done
  shopt -u dotglob nullglob

  # A fresh account has nothing to migrate: mark every shipped migration done
  mkdir -p ~/.local/state/omarchy/migrations
  for migration in "$OMARCHY_PATH"/migrations/*.sh; do
    touch ~/.local/state/omarchy/migrations/"$(basename "$migration")"
  done

  log "Running omarchy-provision-user"
  set +e
  OMARCHY_THEME_HEADLESS=1 omarchy-provision-user --force 2>&1 | tee "$STATE_DIR/provision-user.log"
  rc=${PIPESTATUS[0]}
  set -e
  (( rc == 0 )) || die "omarchy-provision-user failed with $rc (log: $STATE_DIR/provision-user.log)"

  if [[ -n $claude_sum && $(sha256sum ~/.claude/settings.json | cut -d' ' -f1) != "$claude_sum" ]]; then
    die "~/.claude/settings.json changed during provisioning; check it"
  fi
  touch "$STATE_DIR/user-provisioned"
else
  log "User already provisioned; keeping current dotfiles (OMAGEEKO_RESET_USER=1 to reset)"
fi

# ---- Files replaces Nautilus (user part of upstream edge migration 1794330979,
# backported with sles/overlay/patches): a personal mimeapps.list or dock pin that
# still names Nautilus points at Files. Idempotent.
for f in "$HOME/.config/mimeapps.list" "$HOME/.config/omarchy/shell.json"; do
  if [[ -f $f ]] && grep -q 'org\.gnome\.Nautilus' "$f"; then
    sed --follow-symlinks -i -e 's/org\.gnome\.Nautilus\.desktop/folio.desktop/g' -e 's/"org\.gnome\.Nautilus"/"folio"/' "$f"
    log "Files instead of Nautilus in ${f#"$HOME"/}"
  fi
done

# ---- host profile (backs up differing files)
if [[ -d $PROFILE_DIR ]]; then
  while IFS= read -r -d '' f; do
    rel=${f#"$PROFILE_DIR"/}
    dst="$HOME/$rel"
    cmp -s "$f" "$dst" 2>/dev/null && continue
    [[ -e $dst ]] && cp -a --no-preserve=context "$dst" "$dst.bak.$(date +%s)"
    install -Dm644 "$f" "$dst"
    log "Host profile $PROFILE: $rel"
  done < <(find "$PROFILE_DIR" -type f -print0)
fi

# ---- host profile theme (sles/hosts/<profile>/theme), applied only when it differs
theme_file="$OMAGEEKO_SLES/hosts/$PROFILE/theme"
if [[ -f $theme_file ]]; then
  want=$(tr -d '[:space:]' < "$theme_file")
  if [[ $(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null) != "$want" ]]; then
    OMARCHY_THEME_HEADLESS=1 omarchy-theme-set "$want" >/dev/null && log "Theme: $want" || warn "Could not set theme $want"
  fi
fi

# ---- host profile terminal (sles/hosts/<profile>/terminal): what
# omarchy-install-terminal does, minus the package (the SLES layers provide it)
term_file="$OMAGEEKO_SLES/hosts/$PROFILE/terminal"
if [[ -f $term_file ]]; then
  term=$(tr -d '[:space:]' < "$term_file")
  case $term in
    alacritty) desktop_id=Alacritty.desktop ;;
    foot) desktop_id=foot.desktop ;;
    ghostty) desktop_id=com.mitchellh.ghostty.desktop ;;
    kitty) desktop_id=kitty.desktop ;;
    *) die "Unknown terminal in $term_file: $term" ;;
  esac
  command -v "$term" >/dev/null || PATH="$HOME/.local/bin:$PATH" command -v "$term" >/dev/null ||
    die "$term is not installed (Ghostty comes from sles/layers/03-omarchy)"
  [[ -e $HOME/.config/$term || ! -d $OMARCHY_PATH/config/$term ]] || cp -Rpf "$OMARCHY_PATH/config/$term" "$HOME/.config/"
  if [[ $(cat "$HOME/.config/xdg-terminals.list" 2>/dev/null) != "$desktop_id" ]]; then
    echo "$desktop_id" > "$HOME/.config/xdg-terminals.list"
    log "Default terminal: $term ($desktop_id)"
  fi
fi

# ---- SDDM: remember this user and the Omarchy session. Omarchy's greeter theme has only a
# password field and logs in as userModel.lastUser; on a fresh install SDDM has no last user,
# so the login goes out with an empty name ("user unknown"). Upstream never hits this: it
# autologins after the disk unlock. SDDM keeps both keys up to date after each login.
state=/var/lib/sddm/state.conf
want_session=/usr/share/wayland-sessions/omarchy.desktop
if [[ -d /var/lib/sddm ]] && ! { sudo grep -qx "Session=$want_session" "$state" && sudo grep -qx "User=$USER" "$state"; } 2>/dev/null; then
  sudo bash -c "touch $state
    grep -q '^\[Last\]' $state || printf '[Last]\n' >> $state
    sed -i '/^\[Last\]/,/^\[/{/^Session=/d;/^User=/d}' $state
    sed -i '/^\[Last\]/a Session=$want_session\nUser=$USER' $state"
  log "SDDM: remembered user $USER, default session Omarchy (Hyprland uwsm)"
fi
# The greeter reads lastUser only at startup. In an unattended install it started at boot,
# before this layer ran, so it still has an empty user. Restart it, but only while nobody is
# logged in on seat0 (restarting sddm would end a running graphical session).
if systemctl is-active -q sddm.service && greeter_stale && ! seat0_user_session; then
  sudo systemctl restart sddm.service && log "SDDM: greeter restarted to pick up the remembered user"
fi

# Session restore: autosave timer and login offer (docs/session-restore.md)
systemctl --user daemon-reload
systemctl --user enable omageeko-session-restore-save.timer omageeko-session-restore-offer.service 2>/dev/null ||
  warn "Session restore units not enabled"

log "Layer 04 done. Run sles/layers/04-session/verify.sh, then log out and log in to 'Omarchy (Hyprland uwsm)'."
