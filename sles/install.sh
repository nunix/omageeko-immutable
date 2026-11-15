#!/bin/bash
# omageeko on SLES 16.1 Immutable: install everything from a (minimal) registered system.
#
#   preflight -> phase system (one snapshot) -> reboot -> phase user -> verify -> report
#
# Usage: sles/install.sh [options]
#   --phase auto|system|user|verify   default auto: continue where the last run stopped
#   --yes                             no prompts (fix what preflight can fix)
#   --reboot                          reboot when the system phase needs it and resume
#                                     the user phase at boot (omageeko-sles-resume.service)
#   --unattended                      = --yes --reboot
#   --no-final-reboot                 after a resumed user phase, don't reboot into the greeter
#                                     (default: reboot once and check the greeter, tools/greeter-check)
#   --profile <name>                  host profile in sles/hosts/ (default: the one named like this
#                                     machine's DMI product name, e.g. 21K6S0A00C, else kvm-guest)
#   --seed github|none|<user@host>    prebuilt RPMs for an empty local repo (tools/seed-repo):
#                                     github = the published release (default), none = build locally
#   --dry-run                         preflight + resolve the system phase's packages, no changes
#
# State: /var/lib/omageeko/install.state (survives rollbacks; removed when the run ends).
# Log:   ~/.local/state/omageeko/install-<timestamp>.log
# Watch a resumed run: journalctl -u omageeko-sles-resume -f

source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

STATE=/var/lib/omageeko/install.state
# While it exists, sddm.service doesn't start (drop-in written by arm_resume): no greeter while the
# user phase runs after the first reboot, so nobody logs in to a half-installed session.
GREETER_HOLD=/var/lib/omageeko/greeter-hold
RESUME_UNIT=omageeko-sles-resume.service
L="$OMAGEEKO_SLES/layers"

# Host profile: --profile, $OMAGEEKO_HOST_PROFILE, the machine's model (sles/hosts/<DMI product name>), kvm-guest
dmi_profile=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
[[ -n $dmi_profile && -d $OMAGEEKO_SLES/hosts/$dmi_profile ]] || dmi_profile=kvm-guest
phase=auto yes=0 reboot=0 dry=0 seed=github final_reboot=1 from_resume=0 profile=${OMAGEEKO_HOST_PROFILE:-$dmi_profile}
while (( $# )); do
  case $1 in
    --phase) phase=${2:?--phase needs a value}; shift ;;
    --yes) yes=1 ;;
    --reboot) reboot=1 ;;
    --unattended) yes=1; reboot=1 ;;
    --profile) profile=${2:?--profile needs a name}; shift ;;
    --seed) seed=${2:?--seed needs github, none or user@host}; shift ;;
    --no-final-reboot) final_reboot=0 ;;
    --from-resume) from_resume=1 ;;   # set by the resume unit
    --dry-run) dry=1 ;;
    -h|--help) sed -n '2,20s/^# \{0,1\}//p' "$0"; exit 0 ;;
    *) die "Unknown option: $1 (see --help)" ;;
  esac
  shift
done
[[ $phase == @(auto|system|user|verify) ]] || die "Unknown phase: $phase"
[[ -d $OMAGEEKO_SLES/hosts/$profile ]] || die "No host profile $OMAGEEKO_SLES/hosts/$profile"
export OMAGEEKO_HOST_PROFILE=$profile

# ---- log everything
log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omageeko"
mkdir -p "$log_dir"
LOG="$log_dir/install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

# ---- state (key=value lines)
state_get() { [[ -f $STATE ]] && sed -n "s/^$1=//p" "$STATE" | tail -n1; return 0; }
state_set() {
  if [[ -f $STATE ]] && grep -q "^$1=" "$STATE"; then
    sed -i "s|^$1=.*|$1=$2|" "$STATE"
  else
    echo "$1=$2" >> "$STATE"
  fi
}

confirm() {
  (( yes )) && return 0
  [[ -t 0 ]] || return 1
  local a; read -r -p "$1 [y/N] " a; [[ $a == [yY]* ]]
}

# run_step <name> <command...>: once per install run, timed
run_step() {
  local name=$1; shift
  if [[ $(state_get "step.$name") == ok* ]]; then
    log "== $name: done earlier in this run, skipped"
    return 0
  fi
  log "== $name: start"
  local t0=$SECONDS
  # On failure forget the step marks (not the phase): the rerun after a fix repeats this
  # phase's steps, so a fix anywhere (e.g. in what an earlier step deploys) is picked up.
  # Layers are idempotent: unchanged ones are no-ops and take no snapshot.
  "$@" || { sed -i '/^step\./d' "$STATE"; disarm_resume
            die "Step $name failed (log: $LOG). Fix it and rerun sles/install.sh: it continues with this phase."; }
  state_set "step.$name" "ok $((SECONDS - t0))s"
  log "== $name: done in $((SECONDS - t0))s"
}

# ---- preflight (§3.1): checks, no changes unless --yes fixes something
preflight() {
  log "Preflight"
  local id ver variant
  id=$(. /etc/os-release; echo "$ID"); ver=$(. /etc/os-release; echo "$VERSION_ID")
  variant=$(. /etc/os-release; echo "${VARIANT_ID:-}")
  [[ $id == sles && $ver == 16.1 && $variant == transactional ]] ||
    die "Needs SLES 16.1 Immutable (found $id $ver ${variant:-mutable})"
  require_sles_immutable

  local products
  products=$(sudo SUSEConnect -s 2>/dev/null) || die "SUSEConnect -s failed: register the system first (sudo SUSEConnect -r <code>)"
  registered() { python3 -c 'import json,sys
sys.exit(0 if any(p["identifier"]==sys.argv[1] and p["version"]=="16.1" and p["status"]=="Registered"
                  for p in json.load(sys.stdin)) else 1)' "$1" <<<"$products"; }
  registered SLES ||
    die "SLES 16.1 is not registered: sudo SUSEConnect -r <code>"
  if ! registered PackageHub; then
    confirm "Package Hub is not registered. Run 'sudo SUSEConnect -p PackageHub/16.1/x86_64' now?" ||
      die "Package Hub is required: sudo SUSEConnect -p PackageHub/16.1/x86_64"
    sudo SUSEConnect -p PackageHub/16.1/x86_64
  fi
  log "  registered: SLES 16.1 + Package Hub"

  if ! command -v podman >/dev/null || ! command -v distrobox >/dev/null; then
    cat >&2 <<'MSG'
podman/distrobox are missing (select the "Container Runtime (podman)" pattern at install time).
The builders run in podman, so they must be on the host before the system phase:
with --yes they are installed in their own snapshot, then a reboot is needed.
MSG
    (( yes )) || die "Rerun with --yes, or install them and reboot"
    host_install podman distrobox
    state_set phase podman-pending
    do_reboot "podman/distrobox installed"
  fi
  log "  podman, distrobox present"

  local u
  for u in https://src.opensuse.org https://github.com https://dl.flathub.org; do
    curl -fsSI --max-time 20 -o /dev/null "$u" || die "No network access to $u"
  done
  log "  network: src.opensuse.org, github.com, flathub"

  local var_free home_free
  var_free=$(df -BG --output=avail /var | tail -n1 | tr -dc 0-9)
  home_free=$(df -BG --output=avail "$HOME" | tail -n1 | tr -dc 0-9)
  (( var_free >= 20 )) || die "/var needs 20 GiB free (has ${var_free} GiB)"
  (( home_free >= 5 )) || die "$HOME needs 5 GiB free (has ${home_free} GiB)"
  log "  disk: /var ${var_free} GiB free, home ${home_free} GiB free"

  local f
  for f in "$OMAGEEKO_IMM/packages/omageeko-sles" "$OMAGEEKO_ROOT/packages/omageeko" \
           "$OMAGEEKO_ROOT/upstream.lock" "$OMAGEEKO_ROOT/packages.map" "$OMAGEEKO_ROOT/tools/omageeko-bump"; do
    [[ -e $f ]] || die "Checkout incomplete: $f missing (git submodule update --init, or sles/tools/sync-guest)"
  done
  log "  host profile: $profile (machine: $(cat /sys/class/dmi/id/product_name 2>/dev/null || echo '?')$(systemd-detect-virt -q && echo ', virtual'))"
  log "  checkout: $OMAGEEKO_IMM (omageeko $(cat "$OMAGEEKO_ROOT/.omageeko-commit" 2>/dev/null || git -C "$OMAGEEKO_ROOT" rev-parse --short HEAD 2>/dev/null || echo '?'))"

  if reboot_pending && [[ $(state_get phase) != system-done ]]; then
    warn "  a snapshot is already pending: the system phase continues it (no second snapshot)"
  fi
}

# ---- dry run: the system phase's packages in one throwaway transaction
dry_run() {
  if reboot_pending; then
    warn "A snapshot is pending; skipping the package resolution (it would have to continue that snapshot)"
    return 0
  fi
  local pkgs=() f
  for f in "$L/00-bootstrap/host.packages" "$L/01-base/host.packages"; do
    mapfile -t -O "${#pkgs[@]}" pkgs < <(grep -vE '^[[:space:]]*(#|$)' "$f")
  done
  [[ $(target_dm) == none ]] && pkgs+=(sddm-qt6)
  if [[ -f $OMAGEEKO_REPO_DIR/repodata/repomd.xml ]]; then
    ensure_local_repo
    ensure_repo_registered
    for f in "$L/01b-hyprland/install.sh" "$L/02-build-rpms/install.sh"; do
      read -r -a extra < <(sed -n 's/^INSTALL=(\(.*\))$/\1/p' "$f")
      pkgs+=("${extra[@]}")
    done
    pkgs+=(omageeko-sles)
  else
    warn "No local repo yet (not seeded, nothing built): only SLES packages are resolved"
  fi
  log "Resolving ${#pkgs[@]} packages (snapshot dropped afterwards)"
  sudo transactional-update --non-interactive --drop-if-no-change run \
    zypper --non-interactive install --dry-run --no-recommends --allow-vendor-change "${pkgs[@]}" || true
  reboot_pending && die "dry run left a pending snapshot; check 'snapper list'"
  log "Dry run done; nothing changed"
}

# ---- resume unit: lives in the pending snapshot, so it exists after the reboot.
# ExecStart is bash, not the script: SELinux doesn't let systemd (init_t) exec a
# user_home_t file; bash (bin_t) runs as unconfined_service_t and reads the script.
arm_resume() {
  local uid; uid=$(id -u)
  local unit="[Unit]
Description=omageeko SLES install: user phase
After=network-online.target
Wants=network-online.target
ConditionPathExists=$STATE

[Service]
Type=oneshot
User=$USER
Environment=XDG_RUNTIME_DIR=/run/user/$uid
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus
Environment=HOME=$HOME
ExecStartPre=+/usr/bin/loginctl enable-linger $USER
ExecStartPre=+/usr/bin/systemctl start user@$uid.service
# progress on the screen: the greeter is held (GREETER_HOLD) until this ends
StandardOutput=journal+console
StandardError=journal+console
ExecStart=/usr/bin/bash $OMAGEEKO_SLES/install.sh --phase user --yes --from-resume --profile $profile$( (( final_reboot )) || echo ' --no-final-reboot')
ExecStartPost=+/usr/bin/systemctl disable $RESUME_UNIT
ExecStopPost=+/usr/bin/loginctl disable-linger $USER
ExecStopPost=+/usr/bin/rm -f $GREETER_HOLD
TimeoutStartSec=3h

[Install]
WantedBy=multi-user.target"
  log "Arming $RESUME_UNIT for the next boot (greeter held until it ends)"
  tu_run "install -Dm644 /dev/stdin /etc/systemd/system/$RESUME_UNIT <<'OMAGEEKO_EOF'
$unit
OMAGEEKO_EOF
install -Dm644 /dev/stdin /etc/systemd/system/sddm.service.d/50-omageeko-install-hold.conf <<'OMAGEEKO_EOF'
# omageeko install (sles/install.sh): no greeter while the user phase runs after a reboot.
# The file exists only during that phase; harmless otherwise.
[Unit]
ConditionPathExists=!$GREETER_HOLD
OMAGEEKO_EOF
systemctl enable $RESUME_UNIT"
  touch "$GREETER_HOLD"
}

disarm_resume() {
  if [[ -f /etc/systemd/system/$RESUME_UNIT ]]; then
    sudo systemctl disable "$RESUME_UNIT" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/$RESUME_UNIT"
    sudo systemctl daemon-reload
  fi
}

do_reboot() {
  if (( reboot )); then
    arm_resume
    log "$1: rebooting; the user phase resumes at boot (journalctl -u $RESUME_UNIT -f)"
    sudo systemctl reboot
    exit 0
  fi
  log "$1: reboot to activate the new snapshot, then run: sles/install.sh (it continues with the user phase)"
  exit 0
}

phase_system() {
  case $seed in
    none) ;;
    github) run_step seed "$OMAGEEKO_SLES/tools/seed-repo" github --if-empty ;;
    *) run_step seed "$OMAGEEKO_SLES/tools/seed-repo" "$seed" ;;
  esac
  run_step 00-bootstrap "$L/00-bootstrap/install.sh" --phase system
  run_step 01-base.system "$L/01-base/install.sh" --phase system
  run_step 01b-hyprland "$L/01b-hyprland/install.sh"
  run_step 02-build-rpms "$L/02-build-rpms/install.sh"
  run_step 03-omarchy.system "$L/03-omarchy/install.sh" --phase system
  run_step 05-hardware.system "$L/05-hardware/install.sh" --phase system
  if reboot_pending; then
    local n; n=$(sudo snapper --csvout list --columns number,default | awk -F, '$2=="yes"{print $1}')
    state_set snapshot "$n"
    log "Pending snapshot #$n, newest packages:"
    # (head closes the pipe early: SIGPIPE + pipefail must not end the run)
    { sudo rpm --root "/.snapshots/$n/snapshot" -qa --last 2>/dev/null | head -n 15 | sed 's/^/    /'; } || true
  else
    log "The system phase changed nothing on the host (no snapshot)"
  fi
  state_set phase system-done
}

phase_user() {
  reboot_pending && die "A snapshot is still pending: reboot first (the user phase needs the new host packages)"
  (( from_resume )) && log "omageeko: finishing the install (user phase, a few minutes). Don't power off: the machine reboots once more into the greeter."
  run_step 01-base.user "$L/01-base/install.sh" --phase user
  run_step 03-omarchy.user "$L/03-omarchy/install.sh" --phase user
  run_step 04-session "$L/04-session/install.sh"
  run_step 05-hardware.user "$L/05-hardware/install.sh" --phase user
  # Safety net: default SELinux labels for everything the user phase wrote
  # (the user phase may run from a system unit, whose /tmp files get other labels)
  log "Restoring SELinux labels under $HOME"
  sudo /usr/sbin/restorecon -R "$HOME"
  # No greeter this boot and none held (a rerun after a failed resume): start it, so verify
  # sees the real state and the machine ends at a login screen
  if [[ ! -e $GREETER_HOLD ]] && ! systemctl is-active -q display-manager.service; then
    sudo systemctl start display-manager.service && log "Greeter started" || warn "Could not start the greeter"
  fi
  state_set phase user-done
}

verify_all() {
  local v failed=()
  for v in "$L"/*/verify.sh; do
    local name; name=$(basename "$(dirname "$v")")
    log "== verify $name"
    "$v" || failed+=("$name")
  done
  (( ${#failed[@]} == 0 )) || { warn "verify FAILED: ${failed[*]}"; return 1; }
  log "All layers verified"
}

report() {
  log "Report"
  {
    echo "  started:      $(state_get started)"
    echo "  finished:     $(date -Is)"
    echo "  profile:      $profile"
    echo "  host:         $(rpm -qa | wc -l) packages; snapshot $(state_get snapshot) $( [[ -n $(state_get snapshot) ]] || echo '(none needed)')"
    echo "  hyprland:     $(rpm -q --qf '%{VERSION}' hyprland 2>/dev/null)"
    echo "  omarchy:      $(omarchy_release)"
    echo "  dm:           $(readlink /etc/systemd/system/display-manager.service | xargs -r basename)"
    echo "  steps:"
    sed -n 's/^step\.\(.*\)=ok \(.*\)/    \1 \2/p' "$STATE"
    echo "  log:          $LOG"
  } | tee "$log_dir/install-report.txt"
}

# Verify failed: forget the step marks so the next install.sh (after a fix) reruns every
# layer - they are idempotent and skip what is already in place - and disarm the resume
# unit, so a failure at boot can't turn into a rerun/reboot loop.
verify_failed() {
  sed -i '/^step\./d; /^phase=/d' "$STATE"
  rm -f "$GREETER_HOLD"
  disarm_resume
  die "Install finished with verify failures. Fix them and rerun sles/install.sh (all layers rerun; unchanged ones are no-ops)."
}

finish() {
  report
  sudo rm -f "$STATE"
  rm -f "$GREETER_HOLD"
  disarm_resume
  if (( from_resume && final_reboot )); then
    final_reboot_into_greeter
  fi
  # no greeter this boot (held during a resume, or a rerun after a failed one): start it now
  if ! systemctl is-active -q display-manager.service; then
    sudo systemctl start display-manager.service || warn "Could not start the greeter: sudo systemctl start display-manager"
  fi
  log "Done. Log out/in (or reboot) and pick the Omarchy session."
}

# After a resumed (unattended) install: reboot once more, so the machine ends where a person
# would leave it, and prove the boot path to a working greeter (display-manager.service ->
# sddm.service on VT1, remembered user). A one-shot unit runs tools/greeter-check after boot
# and writes /var/lib/omageeko/greeter-check.txt.
GREETER_CHECK_UNIT=omageeko-sles-greeter-check.service
final_reboot_into_greeter() {
  sudo rm -f /var/lib/omageeko/greeter-check.txt
  sudo install -Dm644 /dev/stdin "/etc/systemd/system/$GREETER_CHECK_UNIT" <<UNIT
[Unit]
Description=omageeko SLES install: check the greeter once after the final reboot
After=display-manager.service

[Service]
# exec, not oneshot: boot must finish (getty@tty1 starts then) while the check waits
Type=exec
ExecStart=/usr/bin/bash $OMAGEEKO_SLES/tools/greeter-check --after-boot --user $USER --out /var/lib/omageeko/greeter-check.txt
ExecStopPost=/usr/bin/systemctl disable $GREETER_CHECK_UNIT
ExecStopPost=/usr/bin/rm -f /etc/systemd/system/$GREETER_CHECK_UNIT

[Install]
WantedBy=multi-user.target
UNIT
  sudo systemctl daemon-reload
  sudo systemctl enable "$GREETER_CHECK_UNIT" 2>/dev/null
  log "Install complete. Final reboot into the greeter; result in /var/lib/omageeko/greeter-check.txt"
  sudo systemctl reboot
  exit 0
}

# ---- main
preflight
(( dry )) && { dry_run; exit 0; }

ensure_local_repo
[[ -f $STATE ]] || { echo "started=$(date -Is)" > "$STATE"; state_set user "$USER"; state_set profile "$profile"; }

case $phase in
  verify) verify_all; exit ;;
  system) phase_system; reboot_pending && do_reboot "System phase done"; exit 0 ;;
  user) phase_user; verify_all || verify_failed; finish; exit 0 ;;
esac

# auto
case $(state_get phase) in
  ""|podman-pending) phase_system ;;
esac
reboot_pending && do_reboot "System phase done"
phase_user
verify_all || verify_failed
finish
