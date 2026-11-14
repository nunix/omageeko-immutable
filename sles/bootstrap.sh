#!/bin/bash
# omageeko on SLES 16.1 Immutable, from nothing: fetch the code and run the unattended install.
# For a freshly installed, registered SLES 16.1 Immutable (minimal is fine) with no git.
#
#   curl -fsSLo /tmp/omageeko-bootstrap.sh https://raw.githubusercontent.com/nunix/omageeko-immutable/main/sles/bootstrap.sh
#   bash /tmp/omageeko-bootstrap.sh
#
# Options: --ref <branch|tag|commit>   what to fetch (default main)
#          --fetch-only                fetch the code, don't install
#          --profile <name>            host profile (sles/hosts/, default kvm-guest)
#          --seed github|none|<u@h>    prebuilt RPMs (default github: the published release)
#          --dest <dir>                checkout location (default ~/omageeko-immutable)
#
# What it does:
#   1. checks the system (SLES 16.1 Immutable, not root) and sudo; the install needs
#      passwordless sudo (the user phase resumes from a system unit after a reboot), so it
#      offers to add /etc/sudoers.d/90-omageeko for this user, as the Agama profile would
#   2. downloads omageeko-immutable at <ref> and the omageeko submodule at the commit pinned
#      there (GitHub tarballs leave submodules out)
#   3. starts sles/install.sh --unattended detached (an ssh drop can't kill it) and follows
#      its log; the machine reboots twice by itself and ends at the greeter
set -euo pipefail
GH_REPO=${OMAGEEKO_GH_REPO:-nunix/omageeko-immutable}
ref=main fetch_only=0 dest="$HOME/omageeko-immutable" install_args=()
while (( $# )); do
  case $1 in
    --ref) ref=${2:?}; shift ;;
    --fetch-only) fetch_only=1 ;;
    --dest) dest=${2:?}; shift ;;
    --profile|--seed) install_args+=("$1" "${2:?$1 needs a value}"); shift ;;
    -h|--help) sed -n '2,23s/^# \{0,1\}//p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

say() { printf '\e[1;34m[omageeko-bootstrap]\e[0m %s\n' "$*"; }
die() { printf '\e[1;31m[omageeko-bootstrap]\e[0m %s\n' "$*" >&2; exit 1; }

# ---- 1. system and sudo
(( EUID != 0 )) || die "Run as your normal user (the one that will log in), not root."
. /etc/os-release
[[ $ID == sles && $VERSION_ID == 16.1 && ${VARIANT_ID:-} == transactional ]] ||
  die "Needs SLES 16.1 Immutable (found $ID $VERSION_ID ${VARIANT_ID:-mutable})."
for c in curl tar python3; do command -v "$c" >/dev/null || die "$c is missing"; done
if ! sudo -n true 2>/dev/null; then
  say "The install needs passwordless sudo for $USER (it continues from a system unit after reboots)."
  say "Adding /etc/sudoers.d/90-omageeko: '$USER ALL=(ALL) NOPASSWD: ALL'. sudo asks for your password once."
  echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/90-omageeko >/dev/null ||
    die "sudo failed: is $USER in the wheel group (or allowed by sudoers)?"
  sudo chmod 440 /etc/sudoers.d/90-omageeko
  sudo -k; sudo -n true 2>/dev/null || die "Passwordless sudo still doesn't work; check /etc/sudoers.d/90-omageeko"
fi
say "System: SLES 16.1 Immutable, sudo ok"

# ---- 2. code
api="https://api.github.com/repos/$GH_REPO"
sub=$(curl -fsSL "$api/contents/omageeko?ref=$ref" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["sha"], d.get("submodule_git_url") or d.get("git_url",""))') ||
  die "Cannot read the omageeko submodule pin of $GH_REPO@$ref"
sub_sha=${sub%% *} sub_url=${sub#* }
sub_repo=$(sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##' <<<"$sub_url")
[[ $sub_repo == */* ]] || sub_repo=nunix/omageeko
tmp=$(mktemp -d /var/tmp/omageeko-bootstrap.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
say "Fetching $GH_REPO@$ref and $sub_repo@${sub_sha:0:7}"
mkdir -p "$tmp/imm"
curl -fsSL "https://codeload.github.com/$GH_REPO/tar.gz/$ref" | tar -xz -C "$tmp/imm" --strip-components=1
rmdir "$tmp/imm/omageeko" 2>/dev/null || true
mkdir -p "$tmp/imm/omageeko"
curl -fsSL "https://codeload.github.com/$sub_repo/tar.gz/$sub_sha" | tar -xz -C "$tmp/imm/omageeko" --strip-components=1
echo "${sub_sha:0:7}" > "$tmp/imm/omageeko/.omageeko-commit"
[[ -x $tmp/imm/sles/install.sh && -f $tmp/imm/omageeko/upstream.lock ]] || die "Downloaded tree is incomplete"
if [[ -e $dest ]]; then
  old="$dest.before-bootstrap.$(date +%Y%m%d-%H%M%S)"
  mv "$dest" "$old"
  say "Previous checkout moved to $old"
fi
mkdir -p "$(dirname "$dest")"
mv "$tmp/imm" "$dest"
say "Code in $dest"
(( fetch_only )) && { say "--fetch-only: run $dest/sles/install.sh --unattended when ready"; exit 0; }

# ---- 3. install, detached; follow its log until it ends or the machine reboots
out="$HOME/.local/state/omageeko/bootstrap-$(date +%Y%m%d-%H%M%S).out"
mkdir -p "$(dirname "$out")"
setsid nohup "$dest/sles/install.sh" --unattended "${install_args[@]}" > "$out" 2>&1 < /dev/null &
pid=$!
say "Install started (pid $pid). Output: $out"
say "It reboots by itself (after the system phase, and once more at the end). Ctrl-C only stops"
say "following the log. After the first reboot: journalctl -u omageeko-sles-resume -f"
sleep 1
tail --pid="$pid" -n +1 -f "$out" || true
rc=0; wait "$pid" 2>/dev/null || rc=$?
(( rc == 0 )) || die "install.sh stopped with status $rc; fix the cause and rerun $dest/sles/install.sh (it continues where it stopped)"
