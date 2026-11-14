# Shared helpers for the omageeko SLES 16.1 Immutable target. Source it, don't execute it.
# The Tumbleweed layers use ../../lib/common.sh; this file is the SLES counterpart.

set -euo pipefail

# Layout (omageeko-immutable repo): sles/ (this target), packages/ (immutable-only specs),
# omageeko/ (git submodule: the main omageeko repo - shared specs, upstream.lock, packages.map).
OMAGEEKO_IMM="${OMAGEEKO_IMM:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
OMAGEEKO_SLES="$OMAGEEKO_IMM/sles"
OMAGEEKO_ROOT="${OMAGEEKO_ROOT:-$OMAGEEKO_IMM/omageeko}"
# pkg_dir <name>: a spec in this repo wins over the submodule's
pkg_dir() {
  if [[ -d $OMAGEEKO_IMM/packages/$1 ]]; then echo "$OMAGEEKO_IMM/packages/$1"
  else echo "$OMAGEEKO_ROOT/packages/$1"; fi
}
OMAGEEKO_REPO_DIR="/var/lib/omageeko/repo"
OMAGEEKO_REPO_ALIAS="omageeko-local"
# tukit hides /var inside transactions; this drop-in bind-mounts the repo in
OMAGEEKO_TUKIT_CONF="/etc/tukit.conf.d/omageeko.conf"
STAMP_DIR="$OMAGEEKO_REPO_DIR/.stamps"

log() { printf '\e[1;34m[omageeko-sles]\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m[omageeko-sles]\e[0m %s\n' "$*" >&2; }
die() { printf '\e[1;31m[omageeko-sles]\e[0m %s\n' "$*" >&2; exit 1; }

# parse_phase "$@": --phase system|user|all (default all) -> $PHASE; other args -> ARGS[]
# System parts change the host (one pending snapshot); user parts only touch $HOME.
parse_phase() {
  PHASE=all; ARGS=()
  while (( $# )); do
    case $1 in
      --phase) PHASE=${2:-}; shift 2 || die "--phase needs a value" ;;
      --phase=*) PHASE=${1#--phase=}; shift ;;
      *) ARGS+=("$1"); shift ;;
    esac
  done
  [[ $PHASE == @(system|user|all) ]] || die "Unknown phase: $PHASE (system|user|all)"
}

require_sles_immutable() {
  (( EUID != 0 )) || die "Run as your normal user; sudo is used where needed."
  sudo -n true 2>/dev/null || die "Passwordless sudo is required."
  local id variant
  id=$(. /etc/os-release && echo "$ID")
  variant=$(. /etc/os-release && echo "${VARIANT_ID:-}")
  [[ $id == sles && $variant == transactional ]] || die "This target is for SLES Immutable (found $id/$variant)."
}

# The local RPM repo lives on /var (writable, outside root snapshots), owned by the user
# (and /var/lib/omageeko with it: install.state, seeds and markers live there)
ensure_local_repo() {
  local d
  for d in "${OMAGEEKO_REPO_DIR%/*}" "$OMAGEEKO_REPO_DIR"; do
    if [[ ! -d $d || ! -O $d ]]; then
      sudo mkdir -p "$d"
      sudo chown "$USER:" "$d"
    fi
  done
  mkdir -p "$STAMP_DIR"
  if [[ ! -f $OMAGEEKO_TUKIT_CONF ]]; then
    log "Bind-mounting /var/lib/omageeko into transactions ($OMAGEEKO_TUKIT_CONF)"
    sudo mkdir -p "$(dirname "$OMAGEEKO_TUKIT_CONF")"
    echo 'BINDDIRS["omageeko-repo"]="/var/lib/omageeko"' | sudo tee "$OMAGEEKO_TUKIT_CONF" >/dev/null
  fi
}

# Register the repo on the running system (/etc is writable; transactions copy it).
# Called only once repodata exists.
ensure_repo_registered() {
  [[ -f $OMAGEEKO_REPO_DIR/repodata/repomd.xml ]] || die "No repodata in $OMAGEEKO_REPO_DIR yet"
  if ! zypper -q --no-refresh lr "$OMAGEEKO_REPO_ALIAS" &>/dev/null; then
    log "Registering zypper repo $OMAGEEKO_REPO_ALIAS"
    sudo zypper -q --non-interactive addrepo --no-gpgcheck --priority 80 --refresh \
      "dir:$OMAGEEKO_REPO_DIR" "$OMAGEEKO_REPO_ALIAS"
  fi
  sudo zypper -q --non-interactive refresh -r "$OMAGEEKO_REPO_ALIAS" >/dev/null
}

# SCC credentials for SLES BCI containers (container-suseconnect reads them from
# /run/secrets). Root-owned on the host, so they go through podman secrets.
refresh_scc_secrets() {
  sudo test -f /etc/zypp/credentials.d/SCCcredentials || die "System not registered with SCC (SUSEConnect)."
  sudo cat /etc/zypp/credentials.d/SCCcredentials | podman secret create --replace scc-credentials - >/dev/null
  sudo cat /etc/SUSEConnect | podman secret create --replace scc-suseconnect - >/dev/null
}

SCC_RUN_ARGS=(
  --secret scc-credentials,target=/run/secrets/SCCcredentials
  --secret scc-suseconnect,target=/run/secrets/SUSEConnect
  -e ADDITIONAL_MODULES=PackageHub
)

# Build a builder image whose Containerfile needs SCC repos (build-time secrets
# must be files; they live in the user's tmpfs runtime dir only for the build).
build_scc_image() {
  local tag="$1" dir="$2" tmp
  tmp=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/omageeko-scc.XXXXXX")
  sudo cat /etc/zypp/credentials.d/SCCcredentials > "$tmp/SCCcredentials"
  sudo cat /etc/SUSEConnect > "$tmp/SUSEConnect"
  podman build --pull=newer -t "$tag" \
    --secret "id=SCCcredentials,src=$tmp/SCCcredentials" \
    --secret "id=SUSEConnect,src=$tmp/SUSEConnect" \
    -f "$dir/Containerfile" "$dir" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}

# Run one transactional-update session (one new snapshot) with a shell script.
# The change takes effect after a reboot.
# transactional-update exits 0 even when the command inside fails (it only
# discards the snapshot), so success is proven by a marker the script writes
# into the bind-mounted /var/lib/omageeko as its last step.
tu_run() {
  local marker=/var/lib/omageeko/.tu-ok
  ensure_local_repo   # the marker dir must exist and be bind-mounted into the transaction
  sudo rm -f "$marker"
  # A pending (not yet booted) snapshot must be continued, not replaced: a new
  # transaction starts from the running snapshot and would drop its changes
  local base=()
  reboot_pending && base=(--continue)
  # Its exit status is unreliable either way (0 on failure, non-zero on some
  # failures): don't let set -e end the script before the marker check reports
  sudo transactional-update --non-interactive --drop-if-no-change "${base[@]}" run bash -c "set -e
$1
touch $marker" || true
  [[ -f $marker ]] || die "transactional-update command failed (see /var/log/transactional-update.log); no snapshot kept"
  sudo rm -f "$marker"
}

# A newer snapshot is waiting for a reboot
reboot_pending() {
  local default current
  default=$(sudo snapper --csvout list --columns number,default | awk -F, '$2=="yes"{print $1}')
  current=$(sudo snapper --csvout list --columns number,active | awk -F, '$2=="yes"{print $1}')
  [[ -n $default && -n $current && $default != "$current" ]]
}

# Root of the snapshot that boots next: the pending default one, else the running system
target_root() {
  if reboot_pending; then
    echo "/.snapshots/$(sudo snapper --csvout list --columns number,default | awk -F, '$2=="yes"{print $1}')/snapshot"
  else
    echo /
  fi
}
target_rpm() { sudo rpm --root "$(target_root)" "$@"; }

# Display manager of the snapshot that boots next (or of / with "running"):
# sddm, gdm, ... ; "none" when display-manager.service isn't set. SUSE's
# display-manager-legacy.service starts the default-displaymanager alternative.
target_dm() {
  local root link
  [[ ${1:-} == running ]] && root=/ || root=$(target_root)
  link=$(sudo readlink "$root/etc/systemd/system/display-manager.service" 2>/dev/null || true)
  case $link in
    "") echo none ;;
    */display-manager-legacy.service)
      basename "$(sudo readlink "$root/etc/alternatives/default-displaymanager" 2>/dev/null || echo unknown)" ;;
    *) basename "$link" .service ;;
  esac
}

# ---- Builds: lock files + the shared SLES builder image
# Lock entries, one per line, in build order:
#   <pool-name> <commit>   openSUSE packaging (src.opensuse.org/pool/<name>)
#   local <name>           omageeko's own spec (packages/<name>/<name>.spec)
# A stamp per entry records what was built. Once one entry rebuilds, every entry
# after it in the same lock rebuilds too (ABI cascade).
# BUILD_REV: bump when a builder/script change must rebuild everything; plain
# refactors keep it, so they don't cost a full rebuild.
BUILD_REV=2
BUILDER_IMAGE="localhost/omageeko-sles-builder:16.1"
BUILDER_CACHE_VOLUME="omageeko-sles-zypp-cache"

ensure_builder() {
  local dir="$OMAGEEKO_SLES/builder" stamp
  stamp=$(sha256sum "$dir/Containerfile" | cut -d' ' -f1)
  if [[ ${OMAGEEKO_REBUILD_IMAGE:-} == 1 ]] || ! podman image exists "$BUILDER_IMAGE" ||
     [[ $(cat "$STAMP_DIR/builder-image" 2>/dev/null) != "$stamp" ]]; then
    log "Building $BUILDER_IMAGE"
    build_scc_image "$BUILDER_IMAGE" "$dir"
    echo "$stamp" > "$STAMP_DIR/builder-image"
  fi
  refresh_scc_secrets
}

# in_builder <layer-dir> build-pkg.sh args...
in_builder() {
  local layer_dir="$1"; shift
  podman run --rm --security-opt label=disable \
    "${SCC_RUN_ARGS[@]}" \
    -v "$OMAGEEKO_ROOT:/src:ro" -v "$OMAGEEKO_IMM:/imm:ro" -v "$layer_dir:/layer:ro" -v "$OMAGEEKO_REPO_DIR:/repo" \
    -v "$BUILDER_CACHE_VOLUME:/var/cache/zypp" \
    "$BUILDER_IMAGE" bash /imm/sles/lib/build-pkg.sh "$@"
}

repo_version() {
  zypper --no-refresh -q info "$1" 2>/dev/null | awk '/^Version/ { print $3; exit }'
}

# lock_entries <lockfile>: prints "kind name commit" lines
lock_entries() {
  local a b
  while read -r a b _; do
    [[ -z $a || $a == \#* ]] && continue
    if [[ $a == local ]]; then echo "local $b -"; else echo "pool $a $b"; fi
  done < "$1"
}

entry_stamp() {
  local layer_dir="$1" kind="$2" name="$3" commit="$4"
  {
    echo "rev $BUILD_REV $kind $commit"
    if [[ -d $layer_dir/patches/$name ]]; then
      (cd "$layer_dir/patches/$name" && find . -type f -print0 | sort -z | xargs -0 sha256sum)
    fi
    if [[ $kind == local ]]; then
      local dir; dir=$(pkg_dir "$name")
      (cd "$dir" && find . -type f ! -name rebuild-on -print0 | sort -z | xargs -0 sha256sum)
      # ABI-bound dependencies (e.g. hyprland for the titlebars plugin, Qt for quickshell)
      if [[ -f $dir/rebuild-on ]]; then
        while read -r dep; do
          [[ -n $dep ]] && echo "$dep $(repo_version "$dep")"
        done < "$dir/rebuild-on"
      fi
    fi
  } | sha256sum | cut -d' ' -f1
}

# build_lock <layer-id> <layer-dir> <lockfile> [check]
# Env: OMAGEEKO_REBUILD=all | "name1 name2" forces rebuilds.
#      OMAGEEKO_RESTAMP=1 records stamps without building (only after a refactor
#      that doesn't change the artifacts).
build_lock() {
  local id="$1" layer_dir="$2" lock="$3" mode="${4:-build}"
  local log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omageeko/$id"
  mkdir -p "$log_dir"
  local kind name commit stamp out rc=0 cascade=0 built=()
  while read -r kind name commit; do
    [[ $commit == - ]] && commit=""
    if [[ $mode == check ]]; then
      if out=$(in_builder "$layer_dir" --check "$kind" "$name" $commit 2>&1); then
        grep -E '^>>> \[.*check|^    ' <<<"$out"
      else
        rc=1
        grep -qE '^    MISSING' <<<"$out" && grep -E '^>>> \[.*check|^    ' <<<"$out" || tail -n 5 <<<"$out"
      fi
      continue
    fi
    stamp=$(entry_stamp "$layer_dir" "$kind" "$name" "$commit")
    if [[ ${OMAGEEKO_RESTAMP:-} == 1 ]]; then
      echo "$stamp" > "$STAMP_DIR/$id-$name"; continue
    fi
    if (( ! cascade )) && [[ ${OMAGEEKO_REBUILD:-} != all && " ${OMAGEEKO_REBUILD:-} " != *" $name "* ]] &&
       [[ $(cat "$STAMP_DIR/$id-$name" 2>/dev/null) == "$stamp" ]]; then
      continue
    fi
    cascade=1
    log "Building $name ($kind${commit:+ ${commit:0:12}}) - log: $log_dir/$name.log"
    if ! in_builder "$layer_dir" "$kind" "$name" $commit > "$log_dir/$name.log" 2>&1; then
      tail -n 30 "$log_dir/$name.log" >&2
      die "Build of $name failed (full log: $log_dir/$name.log)"
    fi
    echo "$stamp" > "$STAMP_DIR/$id-$name"
    built+=("$name")
  done < <(lock_entries "$lock")
  if [[ $mode == check ]]; then
    log "Check done (MISSING lines name what SLES lacks; entries later in the lock may provide them)."
    return $rc
  fi
  [[ ${OMAGEEKO_RESTAMP:-} == 1 ]] && { log "Restamped $(basename "$lock")"; return 0; }
  (( ${#built[@]} )) && log "Built: ${built[*]}" || log "All packages up to date with $(basename "$lock")"
}

# install_from_repo <layer-id> pkg... : install/update in one snapshot, judged
# against the snapshot that boots next; no snapshot when nothing changed.
install_from_repo() {
  local id="$1"; shift
  ensure_repo_registered
  local repo_state missing=() p
  repo_state=$(sha256sum "$OMAGEEKO_REPO_DIR/repodata/repomd.xml" | cut -d' ' -f1)
  for p in "$@"; do target_rpm -q "$p" &>/dev/null || missing+=("$p"); done
  if (( ${#missing[@]} == 0 )) && [[ $(cat "$STAMP_DIR/$id-installed" 2>/dev/null) == "$repo_state" ]]; then
    log "Next boot already has these packages at the current repo state; no snapshot needed"
    return 0
  fi
  log "Transactional install for $id (${#missing[@]} missing: ${missing[*]:-none})"
  # --allow-vendor-change: omageeko-local deliberately replaces SLES packages that
  # are too old (libxkbcommon0, see 01b NOTES.md); priority 80 makes it win
  tu_run "zypper --non-interactive refresh -r $OMAGEEKO_REPO_ALIAS
zypper --non-interactive install --no-recommends --allow-vendor-change $*
zypper --non-interactive update --no-recommends --allow-vendor-change -r $OMAGEEKO_REPO_ALIAS"
  echo "$repo_state" > "$STAMP_DIR/$id-installed"
}

# host_install pkg... : SLES/Package Hub packages for the host, only those the
# next boot doesn't have yet, in one snapshot
host_install() {
  local missing=() p
  for p in "$@"; do target_rpm -q --whatprovides "$p" &>/dev/null || missing+=("$p"); done
  (( ${#missing[@]} )) || { log "Host packages already present: $*"; return 0; }
  log "Transactional install of host packages: ${missing[*]}"
  tu_run "zypper --non-interactive install --no-recommends ${missing[*]}"
}

# host_remove pkg... : remove host packages the next boot still has, in one snapshot
host_remove() {
  local present=() p
  for p in "$@"; do target_rpm -q "$p" &>/dev/null && present+=("$p"); done
  (( ${#present[@]} )) || return 0
  log "Transactional removal of host packages: ${present[*]}"
  tu_run "zypper --non-interactive remove --clean-deps ${present[*]}"
}

finish_layer() {
  if reboot_pending; then
    warn "A new snapshot is waiting: reboot to activate it, then run $1"
  else
    log "Done. Run $1"
  fi
}

# ---- Published binary repo (GitHub releases of omageeko-immutable)
OMAGEEKO_GH_REPO="${OMAGEEKO_GH_REPO:-nunix/omageeko-immutable}"
OMAGEEKO_REPO_ASSET="omageeko-repo.tar"
# Stamps that describe one machine's install state; they never travel with a repo
OMAGEEKO_LOCAL_STAMPS=('*-installed' 03-userland 03-ghostty-deployed builder-image)

# repo_key: names the release that fits this checkout: the build inputs that pin
# versions (locks, upstream pin, BUILD_REV). Only picks a release: the per-entry
# stamps still decide what gets rebuilt, so a near miss costs builds, never correctness.
repo_key() {
  {
    echo "rev $BUILD_REV"
    cat "$OMAGEEKO_SLES/layers/01b-hyprland/hyprland.lock" \
        "$OMAGEEKO_SLES/layers/02-build-rpms/build.lock" \
        "$OMAGEEKO_SLES/layers/03-omarchy/build.lock" \
        "$OMAGEEKO_ROOT/upstream.lock"
  } | sha256sum | cut -c1-12
}

# omarchy_release: "v4.5.0 (ac2690c)" from the pin. Upstream's own version file is
# not bumped by releases (it still says 4.0.0.alpha at v4.5.0).
omarchy_release() {
  local rel commit
  rel=$(sed -n 's/^release=//p' "$OMAGEEKO_ROOT/upstream.lock")
  commit=$(sed -n 's/^commit=//p' "$OMAGEEKO_ROOT/upstream.lock")
  echo "${rel:-?} (${commit:0:7})"
}

# ---- SDDM greeter state
# greeter_pid: the running greeter (as user sddm; comm is truncated to 15 chars), empty when none
greeter_pid() { pgrep -u sddm '^sddm-greeter' 2>/dev/null | head -n1 || true; }
# seat0_user_session: someone is logged in graphically on seat0
seat0_user_session() {
  loginctl list-sessions --no-legend 2>/dev/null | awk '$4=="seat0" && $6=="user" {f=1} END {exit !f}'
}
# greeter_stale: the greeter started before state.conf was last written, so it still shows
# the old (possibly empty) remembered user. Omarchy's theme has no user field: a stale greeter
# logs in as "" ("user unknown"). Start time: the greeter process, else sddm.service.
greeter_stale() {
  local pid start mtime ts
  mtime=$(sudo stat -c %Y /var/lib/sddm/state.conf 2>/dev/null) || return 1
  pid=$(greeter_pid)
  if [[ -n $pid ]]; then
    start=$(( $(date +%s) - $(ps -o etimes= -p "$pid" | tr -d ' ') ))
  else
    ts=$(systemctl show -P ActiveEnterTimestamp sddm.service 2>/dev/null)
    [[ -n $ts ]] || return 1
    start=$(date -d "$ts" +%s) || return 1
  fi
  (( start < mtime ))
}
