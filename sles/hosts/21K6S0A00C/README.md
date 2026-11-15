# 21K6S0A00C — Lenovo ThinkPad P14s Gen 4 (AMD), bare metal

Picked automatically by `sles/install.sh` when `/sys/class/dmi/id/product_name` is
`21K6S0A00C` (or with `--profile 21K6S0A00C`). Taken from the same laptop's live
Tumbleweed setup on 2026-11-15 (omageeko `hosts/21K6S0A00C` + the live `~/.config`).

User files (layer 04 copies them into `$HOME`; differing files are backed up):

- `hypr/monitors.lua`: the desk with 3 screens. DP-8 (Samsung C27G7, 2560x1440@240) |
  DP-9 + HDMI-A-1 (Odyssey G9 `LS49AG95` in picture-by-picture: two 2560x1440@60 halves).
  DP-9 anchors at 0x0, the laptop panel eDP-1 sits centred below. The catch-all rule
  (`output = ""`, preferred, auto) covers the laptop alone and any other screen. Scale
  auto, `GDK_SCALE=2`. Omarchy's internal-monitor toggle (Super menu) decides whether
  eDP-1 is on while docked; undocked it's the only screen.
  The DP-8/DP-9 names come from the dock's DP MST enumeration under amdgpu; if SLES
  names them differently, `hyprctl monitors` shows the new names: adjust this file.
- `hypr/bindings.lua`: the MX thumb-wheel workspace carousel, column swap, autoclicker
  (`~/.local/bin/autoclicker`, not part of omageeko: the key does nothing until it's
  there), legacy dictation keys (only when dictation is installed).
- `hypr/input.lua`: Mac-like touchpad (natural scroll, clickfinger, 3-finger swipes).
- `omarchy/shell.json`: the live bar layout; dock pins Files (`folio`) and Brave
  (`brave-browser`) instead of Nautilus and Chromium.
- `omageeko/monitor-wake-kick`: the G9 drops HDMI-A-1 after deep standby and stays dark;
  `omageeko-monitor-wake-kick.service` (omageeko-hardware, enabled by layer 05) cycles
  DPMS when it reconnects.
- `theme` lumon, `terminal` ghostty, `browser` brave.

Host (layer 05, one snapshot): `host.packages` (fingerprint, bolt, fwupd, SOF firmware,
ddcutil), plus on every bare-metal machine `omageeko-hardware` (UCM audio labels, display
I2C access, G9 wake kick, Bluetooth LE Device Privacy Mode) and `bluez-tools`
(`bt-agent`, the pairing agent Omarchy's `bt-agent.service` runs); power-profiles-daemon
and the BLE privacy timer enabled.

Manual after the install: fingerprint enrollment (`omarchy-setup-security-fingerprint`),
Bluetooth pairing (MX Master / MX Keys reconnect after sleep thanks to the privacy timer).
