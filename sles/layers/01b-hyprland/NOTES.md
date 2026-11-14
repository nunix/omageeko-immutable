# SLES layer 01b — notes

Status: **built and installed into snapshot #4 (2026-11-13)**, waiting for the first reboot + `verify.sh`.
20 pool packages build in the container in about 25 min on 8 vCPUs; the transaction installs 25 new packages and replaces 3 xkbcommon libraries.

## Design
- Source = openSUSE's own packaging at pinned commits of `src.opensuse.org/pool/<name>` (branch
  `factory`), so the stack matches what omageeko runs on Tumbleweed (Hyprland 0.57.2 at the time
  of writing) and gets Tumbleweed's patches for free. SLES fixes go in `patches/<name>/`.
- One fresh container per package keeps BuildRequires honest. Earlier entries feed later ones
  through `/repo` (priority 80 inside the builder).
- Rebuild cascade: when one entry rebuilds, everything after it in the lock rebuilds too (sonames
  across hyprutils/aquamarine/hyprlang move together).
- Interactive debugging: `distrobox create -n hypr-dev -i localhost/omageeko-sles-builder:16.1`
  (it shares `$HOME`; the layer itself uses throwaway `podman run` containers).

## Findings
- **tukit hides `/var`** in transactions; `/etc/tukit.conf.d/` doesn't exist by default. The drop-in
  needs a string key (`BINDDIRS["omageeko-repo"]`); a numeric key in a new file was ignored.
- **pool repos are SHA-256** git repos: `git init --object-format=sha256` before fetching a commit,
  otherwise "couldn't find remote ref".
- Tarballs are in git LFS (`git lfs pull`); the raw/media web endpoints answer 403 to scripts.
- BCI images only see `SLE_BCI`; the host's SCC files as podman secrets +
  `ADDITIONAL_MODULES=PackageHub` add SLES product + Package Hub + Backports.
- **OBS buildtime services**: hyprwayland-scanner, hyprland-guiutils, hyprpicker and uwsm ship
  `<name>-<ver>.obscpio` + `_service` (`tar`/`recompress` in buildtime mode) instead of a tarball.
  `build-pkg.sh` reproduces it: unpack the cpio, tar it under the name the spec's Source expects.
- **GCC 16**: Hyprland 0.57 uses C++26 `std::string::subview` (libstdc++ 16). SLES defaults to GCC 15
  but ships `gcc16-c++`, and its runtime `libstdc++6` is already from GCC 16, so the builder sets
  `CC=gcc-16 CXX=g++-16` for everything (same compiler as Tumbleweed).
- **transactional-update exits 0 when the command inside fails** (it only discards the snapshot).
  `tu_run` writes a marker into the bind-mounted `/var/lib/omageeko` as the last step and checks it.
- Replacing SLES packages needs `--allow-vendor-change` (zypper otherwise stops at a vendor-change
  problem, which non-interactive mode treats as failure).
- `transactional-update run` without `--drop-if-no-change` keeps an empty snapshot and makes it the
  default; `tu_run` always passes the flag.
- **A pending snapshot must be continued**: a new transaction starts from the *running* snapshot, so
  a second layer run before rebooting would silently drop the first one's changes. `tu_run` passes
  `--continue` while a reboot is pending, and install.sh checks packages in the pending snapshot
  (`target_rpm`) plus a repo-state stamp (`.stamps/01b-installed`), so reruns are no-ops.
- `install.sh --check` output: zypper's "not found in package names. Trying capabilities." is
  informational; only "No provider of" means missing.

## Extra dependencies (SLES 16.1 too old / missing)
| Package | SLES 16.1 | Needed by | Note |
|---|---|---|---|
| wayland-protocols | 1.47 | hyprland (≥ 1.49) | devel-only, stays in the builder |
| libxkbcommon | 1.8.0 | hyprland (≥ 1.11) | **replaces SLES's `libxkbcommon0` on the host** (same soname, also used by KDE) |
| sdbus-cpp | — | hyprland, xdph (≥ 2.0) | |
| glaze | — | hyprland | header-only |
| lua55 | 5.4 only | hyprland (Lua config) | |

## SLES patches
| Package | Patch | Why |
|---|---|---|
| wayland-protocols | `01-no-tests-old-scanner.patch` | 1.50's test suite needs wayland-scanner ≥ 1.25 (SLES: 1.24); building the XML itself needs only ≥ 1.22.90. Avoids replacing SLES's libwayland. |
| lua55 | `01-no-lua-interpreter.patch` | TW's `lua-interpreter` (alts) clashes with SLES `lua54` (pulled in by `lua-macros`) over `/usr/bin/lua{,c}`. Hyprland needs only `liblua5_5-5` + headers. |

## Host footprint (snapshot #4)
omageeko-vendor RPMs: hyprland, hyprland-guiutils, hyprpicker, hyprsunset, xdg-desktop-portal-hyprland,
uwsm, libaquamarine15, libhyprcursor0, libhyprgraphics5, libhyprlang2, libhyprtoolkit6, libhyprutils13,
libhyprwire3, liblua5_5-5, libsdbus-c++2, **libxkbcommon0, libxkbcommon-x11-0, libxkbregistry0 (1.8.0 → 1.13.2,
vendor SUSE → omageeko)**. Everything else came from SLES/Package Hub.

## Next
- Reboot, `verify.sh`, then a first Hyprland start (needs VM 3D acceleration, see the assessment).
- `omarchy-hyprland-titlebars` (layer 02 equivalent) must build against this `hyprland-devel`.
- Hyprland's spec builds with `-DNO_UWSM=True`, so there is no `hyprland-uwsm.desktop`; the omageeko session file (layer 04) provides the uwsm entry.
