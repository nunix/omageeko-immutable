#!/bin/bash
# Build one RPM for SLES 16.1 inside the omageeko SLES builder container.
# Usage (in container):
#   build-pkg.sh [--check] pool <name> <commit>   openSUSE packaging: src.opensuse.org/pool/<name>@<commit>
#   build-pkg.sh [--check] local <name>           omageeko's own spec: packages/<name>/<name>.spec
# --check only reports BuildRequires SLES can't satisfy.
# Mounts: /src = omageeko submodule (ro), /imm = omageeko-immutable checkout (ro), /layer = the calling layer dir (ro), /repo = local RPM repo (rw).
#
# SLES adjustments: /layer/patches/<name>/*.patch, applied with patch -p1 --fuzz=0
# to the package dir (pool checkout or a copy of packages/<name>).

set -euo pipefail

check=0
[[ ${1:-} == --check ]] && { check=1; shift; }
kind="$1" name="$2" commit="${3:-}"
topdir=/tmp/rpmbuild
src=/tmp/src/$name
stamp_ts=$(date -u +%Y%m%d%H%M%S)

echo ">>> [$name] repos"
zypper --non-interactive --quiet --gpg-auto-import-keys refresh >/dev/null || echo ">>> refresh had errors (continuing)"
if [[ -f /repo/repodata/repomd.xml ]]; then
  # Earlier builds satisfy later BuildRequires
  zypper --non-interactive --quiet addrepo --no-gpgcheck --priority 80 dir:/repo omageeko-local
  zypper --non-interactive --quiet refresh -r omageeko-local
fi

rm -rf "$src"
case $kind in
  pool)
    echo ">>> [$name] fetching pool/$name@${commit:0:12}"
    # pool repos on src.opensuse.org use SHA-256 object names (64 hex digits)
    fmt=sha1; (( ${#commit} == 64 )) && fmt=sha256
    git init -q --object-format=$fmt "$src"
    git -C "$src" remote add origin "https://src.opensuse.org/pool/$name.git"
    git -C "$src" fetch -q --depth 1 origin "$commit"
    git -C "$src" -c advice.detachedHead=false checkout -q FETCH_HEAD
    git -C "$src" lfs pull
    ;;
  local)
    pkg=/imm/packages/$name; [[ -d $pkg ]] || pkg=/src/packages/$name
    [[ -f $pkg/$name.spec ]] || { echo ">>> [$name] no packages/$name/$name.spec"; exit 1; }
    mkdir -p "$src"
    cp -a "$pkg"/. "$src/"
    ;;
  *) echo "unknown kind: $kind"; exit 2 ;;
esac

if compgen -G "/layer/patches/$name/*.patch" >/dev/null; then
  for p in /layer/patches/"$name"/*.patch; do
    echo ">>> [$name] SLES patch $(basename "$p")"
    patch -d "$src" -p1 --fuzz=0 --no-backup-if-mismatch < "$p"
  done
fi

spec="$src/$name.spec"
[[ -f $spec ]] || spec=$(ls "$src"/*.spec | head -1)

if [[ $kind == pool ]]; then
  # OBS sets Release; locally "Release: 0" would never upgrade. Same scheme as the
  # Tumbleweed layers: a build timestamp, so every rebuild is newer.
  sed -i -E "s/^(Release:[[:space:]]*).*/\10.omageeko.b$stamp_ts/" "$spec"
fi
# omageeko's own specs end their Release with %{?dist}: same timestamp scheme
rpm_defs=(--define "_topdir $topdir" --define "vendor omageeko" --define "dist .b$stamp_ts"
          --define "disturl omageeko:$kind/$name${commit:+@$commit}")

mapfile -t buildreqs < <(rpmspec "${rpm_defs[@]}" -q --buildrequires "$spec" | sed -E 's/ +([<>=]+) +/\1/')

if (( check )); then
  echo ">>> [$name] BuildRequires check"
  if (( ${#buildreqs[@]} )) && ! out=$(zypper --non-interactive install --dry-run --no-recommends "${buildreqs[@]}" 2>&1); then
    grep -E "nothing provides|No provider" <<<"$out" | sed 's/^/    MISSING /' || echo "$out" | tail -5
    exit 1
  fi
  echo "    all BuildRequires resolvable"
  exit 0
fi

echo ">>> [$name] installing ${#buildreqs[@]} BuildRequires"
(( ${#buildreqs[@]} )) && zypper --non-interactive --quiet install --no-recommends "${buildreqs[@]}"

rm -rf "$topdir"
mkdir -p "$topdir"/{SOURCES,SPECS,BUILD,RPMS,SRPMS}
# Patches and extra files (and subdirectories for local specs) ship next to the spec
(cd "$src" && find . -mindepth 1 -maxdepth 1 ! -name '*.spec' ! -name '.git*' -exec cp -a {} "$topdir/SOURCES/" \;)

# Remote Source URLs (local specs; pool packages carry their tarballs).
# A "#/name" fragment sets the local file name (standard Fedora/SUSE convention).
rpmspec "${rpm_defs[@]}" -P "$spec" | sed -nE 's/^Source[0-9]*:[[:space:]]*((https?|ftp):\/\/.*)$/\1/p' |
  while read -r url; do
    file=${url##*/}
    [[ $url == *'#/'* ]] && file=${url##*#/} && url=${url%%#/*}
    if [[ ! -f $topdir/SOURCES/$file ]]; then
      echo ">>> [$name] fetching $file"
      curl -fsSL --retry 3 -o "$topdir/SOURCES/$file" "$url"
    fi
  done

# OBS "buildtime" services (tar + recompress): turn <name>-<ver>.obscpio into the
# tarball the spec's Source lines name. OBS does this on its build workers.
if compgen -G "$topdir/SOURCES/*.obscpio" >/dev/null; then
  mapfile -t wanted < <(rpmspec "${rpm_defs[@]}" -P "$spec" | sed -nE 's/^Source[0-9]*:[[:space:]]*(.*)$/\1/p' | sed -E 's|.*/||; s|.*#/||')
  for cpio_file in "$topdir"/SOURCES/*.obscpio; do
    base=$(basename "$cpio_file" .obscpio)
    target=""
    for w in "${wanted[@]}"; do [[ $w == "$base".tar* ]] && target=$w; done
    [[ -n $target ]] || { echo ">>> [$name] no Source matches $base.obscpio"; exit 1; }
    echo ">>> [$name] OBS tar service: $(basename "$cpio_file") -> $target"
    work=$(mktemp -d)
    (cd "$work" && cpio -idm --quiet < "$cpio_file")
    case $target in
      *.tar.xz)  tar -C "$work" -cJf "$topdir/SOURCES/$target" "$base" ;;
      *.tar.gz)  tar -C "$work" -czf "$topdir/SOURCES/$target" "$base" ;;
      *.tar.zst) tar -C "$work" --zstd -cf "$topdir/SOURCES/$target" "$base" ;;
      *.tar.bz2) tar -C "$work" -cjf "$topdir/SOURCES/$target" "$base" ;;
      *.tar)     tar -C "$work" -cf "$topdir/SOURCES/$target" "$base" ;;
      *) echo ">>> [$name] unsupported archive type: $target"; exit 1 ;;
    esac
    rm -rf "$work" "$cpio_file"
  done
fi

echo ">>> [$name] building"
rpmbuild "${rpm_defs[@]}" -ba "$spec"

echo ">>> [$name] publishing"
for rpm in "$topdir"/RPMS/*/*.rpm; do
  arch=$(basename "$(dirname "$rpm")")
  mkdir -p "/repo/$arch"
  # One version per package name in the repo: drop older builds of the same RPM
  rpmname=$(rpm -qp --qf '%{NAME}' "$rpm" 2>/dev/null)
  for old in /repo/"$arch"/"$rpmname"-[0-9]*.rpm; do
    [[ -e $old && $(rpm -qp --qf '%{NAME}' "$old" 2>/dev/null) == "$rpmname" ]] && rm -f "$old"
  done
  cp -f "$rpm" "/repo/$arch/"
  echo "    $arch/$(basename "$rpm")"
done
mkdir -p /repo/src
for srpm in "$topdir"/SRPMS/*.src.rpm; do
  srcname=$(rpm -qp --qf '%{NAME}' "$srpm" 2>/dev/null)
  for old in /repo/src/"$srcname"-[0-9]*.src.rpm; do
    [[ -e $old && $(rpm -qp --qf '%{NAME}' "$old" 2>/dev/null) == "$srcname" ]] && rm -f "$old"
  done
  cp -f "$srpm" /repo/src/
done
createrepo_c --quiet --update /repo
