# kvm-guest — SLES 16.1 Immutable test VM (libvirt `sles16.1`)

User files sles/layers/04-session copies into $HOME (existing files are backed up),
mirroring the Hyprland setup of the reference ThinkPad (hosts/21K6S0A00C):

- `hypr/bindings.lua`, `hypr/input.lua`: from hosts/21K6S0A00C (MX thumb-wheel workspace
  carousel, Mac-like touchpad; docs/touchpad-and-mouse.md).
- `omarchy/shell.json`: the reference machine's live bar layout (2026-11-13), dock pin
  `org.gnome.Nautilus` → `folio` (Files, sles/overlay/patches backport).
- `theme`: the Omarchy theme layer 04 applies (the reference machine runs Lumon).
- `browser`: the default browser layer 04 sets (`omarchy-default-browser` semantics): Brave,
  from Flathub (layer 01 adds the `brave` command and `brave-browser.desktop`). Dock pin too.
- `terminal`: the default terminal layer 04 selects (`omarchy-install-terminal` semantics);
  Ghostty, from the userland bundle of layer 03.

Not copied: `monitors.lua` (the desk layout doesn't apply to a VM display; Omarchy's
default `monitors.lua` from skel stays) and `omageeko/monitor-wake-kick`.
