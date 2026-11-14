# Agent prompt — omageeko SLES layer 00: bootstrap

You are (re)building layer 00 of **omageeko** on **SLES 16.1 Immutable**. Read `sles/README.md`
and `sles/PLAN-install.md` first.

## Goal

Give a **minimal** SLES 16.1 Immutable install (registered, Package Hub, pattern
`container_runtime_podman`) the desktop base the later layers assume. The KDE install brought
it implicitly with `kde_plasma`/`x11`/`fonts`:

1. `host.packages`: audio (PipeWire), graphics (Mesa, Vulkan, Xwayland), desktop services
   (udisks2, upower, power-profiles-daemon, bluez, gvfs), XDG plumbing and portals, icon themes,
   Noto fonts, Flatpak, commands Omarchy scripts call (ImageMagick, socat, xsetroot, ...) and the
   runtime libraries of the userland Ghostty bundle. Only what the next boot lacks, via `host_install`.
2. Display manager (decision D-1): **SDDM** like upstream Omarchy — `sddm-qt6` and `sddm.service`
   enabled (`Alias=display-manager.service`). The Omarchy config (Wayland greeter started by
   `start-hyprland` with `/usr/share/sddm/hyprland.lua`, theme `omarchy`) is the
   `omageeko-sles-sddm` subpackage, which layer 03 installs after building it. Only when the next
   boot has no display manager or already uses SDDM (`OMAGEEKO_DM=sddm` forces the switch).
3. `graphical.target` default; rebootmgr `strategy=off` in `/etc/rebootmgr.conf` (decision D-3).

All of it goes into the pending snapshot (`tu_run`, continued by layers 01–03). Nothing changes
when the next boot already matches.

## Rules

- No KDE-only packages. Add a package only when a later layer or Omarchy needs it at runtime and
  nothing pulls it as a dependency (`--no-recommends`!). `sles/tools/probe` shows installed /
  available / missing; `sles/install.sh --dry-run` shows the full resolution.
- Config files are written **inside** the transaction (the package's own copy would win otherwise).

## Done when

`sles/layers/00-bootstrap/verify.sh` passes after the reboot.
