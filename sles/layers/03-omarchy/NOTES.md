# SLES layer 03 — notes (option B: Omarchy in userland)

Status: **applied and verified 2026-11-13**.

## How
- The TW `omageeko` spec builds in the SLES builder (noarch). Its RPMs are **not installed**:
  `rpm_payload` unpacks omageeko, omageeko-settings, omageeko-session and the two font RPMs,
  and `deploy_omarchy_tree`/`deploy_user_integration` (sles/lib/userland.sh) map them:

  | Packaged | Userland |
  |---|---|
  | /usr/share/omarchy, /usr/bin/omarchy-* | ~/.local/share/omarchy (`OMARCHY_PATH`), real files in bin/ |
  | /usr/share/omageeko, /etc/skel | ~/.local/share/omageeko (+ skel/ for layer 04) |
  | /usr/lib/systemd/user, /etc/systemd/user | ~/.config/systemd/user |
  | /usr/share/uwsm/env.d | ~/.config/uwsm/env.d (uwsm reads it) |
  | /etc/mise/conf.d, fontconfig, /etc/xkb, fastfetch | ~/.config/... |
  | fonts, icons, mimeapps.list, xdg-terminal-exec list | ~/.local/share/... |

- `rewrite_paths`: `/usr/share/omarchy` (not `omarchy-platform`), `/usr/share/omageeko` and
  `/usr/bin/om{archy,ageeko}-*` → the userland paths. That also turns upstream's dev-mode checks
  (`!= /usr/share/omarchy`) into "packaged" checks, which is right: the tree is an install,
  not a git checkout. `env-bootstrap` is then patched to always prepend `$OMARCHY_PATH/bin`.
- `omarchy-security-functions` trusts `$OMARCHY_PATH/bin/<cmd>` when it is a real file, so bin/
  must not hold the RPM's symlinks to /usr/bin.
- Host: `omageeko-sles` RPM only (`packages/omageeko-sles`): the SDDM session entry and
  `/etc/pam.d/omarchy-lock-password` (upstream's stack with `common-account`).
- `sles/overlay/` is laid over the tree: SLES `omarchy-pkg-add`/`-drop` + `pkg.sh` (Tumbleweed
  names → `omageeko-twbox` distrobox, Flathub `--user`, Arch box; never the host),
  `omageeko-twbox`, and `omageeko-update` (transactional-update + SLES layers + mise/Flathub/boxes).
- Rerun = redeploy when the RPMs, the overlay or userland.sh changed. No snapshot, no reboot.

## Deliberately not shipped
- Upstream's `/etc/sudoers.d/omarchy-*`: they grant password-less root to `/usr/bin/omarchy-*`;
  with the commands in a user-writable directory that would be root for any user process.
  The affected menu actions (DNS presets, locale generation, browser theme colour, timezone)
  ask for sudo instead.
- `/etc/profile.d/omarchy.sh`: ~/.bashrc and the uwsm env.d cover shells and the session.

## Known gaps
- Root helpers that pin `PATH=/usr/share/omarchy/bin:...` (omarchy-apply-lock, -provision-hardware)
  now point at the user tree; they run as root via sudo only when the user starts them.
- `PACKAGED_PATH=/usr/bin/omarchy-*` self-checks (dns, theme-set-browser-policy, factory reset)
  compare against the user path now; factory reset / boot entries are TW (sdbootutil) code and
  don't apply to SLES (GRUB2 + snapper).

## Backports from upstream edge (sles/overlay/patches)
- `tree-10-files-replaces-nautilus.patch` (795dfb2 + 744e233) and `config-10-...` switch the file
  manager to Files ahead of upstream.lock. Rebased on ac2690c: system.lua and the Dropbox panel had
  moved; the retroarch hunk is left out (omageeko stubs that command). The user part of the
  upstream migration (mimeapps.list, dock pin) runs in layer 04. Drop both when upstream.lock
  contains 795dfb2.
- The SLES host has no `patch`; `apply_patch` runs it in the builder container.

## Ghostty (userland bundle, default terminal)
- Rex (Superlogical) was the first choice: not possible, closed source, macOS/iOS clients only.
- Ghostty publishes official binaries for macOS only; on Linux distros build it. `packages/ghostty`
  builds the 1.3.1 release with official Zig 0.15.2 (SLES has 0.12), dependencies fetched by zig
  (hash-verified) and linked statically. The pool `ghostty` factory branch was still at 1.1.3.
- Never installed: unpacked to `~/.local/opt/ghostty`. Its one missing runtime library,
  libadwaita, comes unpacked from the SLES package into `lib/`, found via RPATH
  (`patchelf --set-rpath '$ORIGIN/../lib'` in the builder), so shells don't inherit an
  LD_LIBRARY_PATH. Desktop entry, D-Bus activation, user unit, icons and `~/.terminfo` point at it.
- SLES ships `tic` in ncurses-devel (not ncurses-utils).
- Selected in layer 04 from the host profile (`sles/hosts/kvm-guest/terminal`).

## 2026-11-14: phase split (install from scratch)
`--phase system` = prepare.sh, builds, `omageeko-sles` (snapshot); `--phase user` = deploy the
userland tree and the Ghostty bundle from the RPMs already in the local repo (no build).
- Fixed 2026-11-14: the Ghostty deploy stamp shared the name `03-ghostty` with the build stamp
  `build_lock` writes for the `ghostty` entry, so each overwrote the other and Ghostty rebuilt on
  every run. The deploy stamp is now `03-ghostty-deployed`.
