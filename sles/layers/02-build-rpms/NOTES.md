# SLES layer 02 — notes

Status: **built, installed (snapshot #5 → #7) and verified 2026-11-13**.

- omageeko's own TW specs (`packages/<name>`) build unchanged on SLES 16.1: quickshell, owe
  (+ owe-lockfeed), omarchy-hyprland-titlebars (against 01b's hyprland-devel), the share
  picker, ttfx. Only two build deps came from the pool: cpptrace, gtk4-layer-shell.
- Same pipeline as 01b (`sles/lib/build-pkg.sh` in `sles/builder`); `local <name>` lock entries
  stamp the spec dir plus the versions in its `rebuild-on` (e.g. hyprland for the plugin).
- SLES's ffmpeg has fewer codecs than Packman's; owe builds and runs against it.

## 2026-11-13: Files (folio)
- `packages/folio`: port of omarchy-pkgs' folio PKGBUILD (Qt 6 file manager, Omarchy's since quattro
  edge 795dfb2). Host package because its plugins load from /usr/share/folio/plugins. QML modules
  are runtime-only, hence explicit Requires (declarative/multimedia imports); QtPdf is a Recommends.
- SUSE's `%cmake_build` passes its arguments to make/ninja as-is: `%cmake_build folio`, not `--target folio`.
