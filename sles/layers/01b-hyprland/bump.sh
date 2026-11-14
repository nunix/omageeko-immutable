#!/bin/bash
# SLES layer 01b - move hyprland.lock to the current Tumbleweed packaging
# Rewrites every commit to the head of the pool "factory" branch (one coherent
# Tumbleweed set) and prints what changed. Then: install.sh, reboot, verify.sh.
# Usage: bump.sh [--dry-run]

set -euo pipefail
LOCK="$(dirname "$(readlink -f "$0")")/hyprland.lock"
dry=0; [[ ${1:-} == --dry-run ]] && dry=1

tmp=$(mktemp)
changed=0
while IFS= read -r line; do
  read -r n c _ <<<"$line" || true
  if [[ -z ${n:-} || $n == \#* ]]; then echo "$line" >> "$tmp"; continue; fi
  head=$(curl -fsS "https://src.opensuse.org/api/v1/repos/pool/$n/branches/factory" |
         grep -oE '"commit":\{"id":"[0-9a-f]{40,64}"' | grep -oE '[0-9a-f]{40,64}')
  [[ -n $head ]] || { echo "  ?? $n: could not read pool/$n factory head" >&2; echo "$line" >> "$tmp"; continue; }
  if [[ $head != "$c" ]]; then
    echo "  $n: ${c:0:12} -> ${head:0:12}  (https://src.opensuse.org/pool/$n/compare/$c...$head)"
    changed=1
  fi
  echo "$n $head" >> "$tmp"
done < "$LOCK"

if (( ! changed )); then echo "hyprland.lock already at factory heads"; rm -f "$tmp"; exit 0; fi
if (( dry )); then rm -f "$tmp"; exit 0; fi
mv "$tmp" "$LOCK"
echo "hyprland.lock updated. Next: install.sh (rebuilds the changed entries and everything after them)."
