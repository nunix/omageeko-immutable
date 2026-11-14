# Agent prompt — omageeko SLES layer 01b: Hyprland stack

You are (re)building layer 01b of **omageeko** on **SLES 16.1 Immutable** (read-only root,
`transactional-update`). Read `sles/README.md` and `docs/sles16-immutable-assessment.md` first.

## Goal

Install the Hyprland stack Omarchy quattro needs (`hyprland`, `hyprland-guiutils`, `hyprpicker`,
`hyprsunset`, `xdg-desktop-portal-hyprland`, `uwsm` and their libraries) on a system that ships none
of it, without putting a toolchain on the host:

1. Build `localhost/omageeko-sles-builder:16.1` from `sles/builder/Containerfile` (SLES BCI 16.1). The
   host's SCC registration goes in as podman secrets, so `container-suseconnect` adds the SLES,
   Package Hub and Backports repos (rootless).
2. For each entry of `hyprland.lock`, in order, run `sles/lib/build-pkg.sh` in a fresh container: fetch
   `https://src.opensuse.org/pool/<name>` at the pinned commit (SHA-256 repos, tarballs in git LFS),
   apply `patches/<name>/*.patch` (fuzz 0), stamp `Release: 0.omageeko.b<timestamp>`, install the
   BuildRequires (SLES + the local repo), `rpmbuild -ba`, publish to `/var/lib/omageeko/repo`.
3. Make the repo visible in transactions (`/etc/tukit.conf.d/omageeko.conf` bind-mounts
   `/var/lib/omageeko`), register it as `omageeko-local` (priority 80), and install/update in **one**
   `transactional-update run` snapshot. Reboot to activate.

`install.sh` does all of it and is also the update path: after `bump.sh` moves the pins to the pool
`factory` heads, rerunning it rebuilds the changed entries **and every entry after them** (ABI
cascade). Nothing changed → no build, no snapshot.

## Rules

- Run as the normal user; passwordless sudo is expected. Never `zypper install` on the host directly:
  host changes go through `transactional-update` (`tu_run`).
- Don't add packages SLES already ships in a sufficient version. Run `install.sh --check` to see
  BuildRequires SLES can't satisfy; add the pool package to `hyprland.lock` before its first user.
- SLES-specific fixes go in `patches/<name>/NN-description.patch` (`diff -u` against the pool
  checkout, `a/`/`b/` prefixes, applies with `--fuzz=0`), with a line in `NOTES.md` saying why.
- Keep the lock coherent: bump all entries together (`bump.sh`), not one library alone.
- Logs: `~/.local/state/omageeko/01b-hyprland/<name>.log`.

## Done when

`sles/layers/01b-hyprland/verify.sh` passes after the reboot.
