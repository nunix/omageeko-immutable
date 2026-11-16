# Hardware

## Host profiles

`sles/hosts/<profile>/` in the checkout, picked by the DMI product name
(`cat /sys/class/dmi/id/product_name`), else `kvm-guest`; override with `--profile`.
- `home/` user files (layer 04 copies them, backing up what differs): `hypr/monitors.lua`,
  `bindings.lua`, `input.lua`, `omarchy/shell.json`, `omageeko/monitor-wake-kick`.
- `theme`, `terminal`, `browser`: applied by layer 04.
- `host.packages`: host packages for this machine (layer 05, one snapshot).
Edit the profile in the checkout, then rerun layer 04 (user files) or 05 (packages): editing only
`~/.config` is lost on reinstall.

## Layer 05 (bare metal, or a VM whose profile has host.packages)

- `omageeko-hardware`: UCM audio labels, display I2C access (ddcutil, external monitor brightness),
  `omageeko-monitor-wake-kick` (Odyssey G9 stays dark after deep standby), Bluetooth LE Device
  Privacy Mode helper + timer (MX devices reconnect after sleep).
- `bluez-tools` (built in layer 02): `bt-agent`, the pairing agent; without it pairing loops.
- power-profiles-daemon enabled.
- iPhone USB tethering: `usbmuxd` + `imobiledevice-tools` (Package Hub) and `ipheth-kmp-default`.
  SLES builds its kernel with `CONFIG_USB_IPHETH` off, so layer 02 builds the driver as a KMP
  (`packages/ipheth`) from SLES's own `kernel-source`; `rebuild-on` rebuilds it on kernel updates.
  Unsigned: loads because Secure Boot is off. Use: Personal Hotspot on, plug in, unlock, **Trust**;
  if nothing shows up, `idevicepair pair` and replug; `nmcli device` lists the ethernet link.

## This laptop: ThinkPad P14s Gen 4 AMD (`21K6S0A00C`)

- Firmware is in a minimal SLES (`kernel-firmware-all`, `ucode-amd`): Radeon 780M, Qualcomm
  QCNFA765 Wi-Fi/BT (ath11k), ACP audio, Realtek dock NICs.
- Wi-Fi (ath11k) needs `qrtr`/`qrtr-mhi`, which SLES ships only in `kernel-default-extra`
  (unsupported modules, `allow_unsupported_modules 1`; the user accepted that). It's in `host.packages`.
- Profile packages: fprintd, fprintd-pam, libfprint (Goodix 27c6:6594), bolt, fwupd, sof-firmware, ddcutil.
- Desk: DP-8 (C27G7) | DP-9 + HDMI-A-1 (Odyssey G9 picture-by-picture halves), eDP-1 below;
  names come from the dock's DP MST: check `hyprctl monitors` and adjust `monitors.lua`.
- Fingerprint sensor is match-on-chip: prints live in the sensor's flash and survive a reinstall
  while `/var/lib/fprint` starts empty, so enrolling fails ("Finger was already enrolled as
  'FP1-…'" in `sudo journalctl -u fprintd`). `sles/tools/fprint-clear-storage` lists them,
  `--wipe` clears the sensor (no snapshot: it fetches the GI typelibs into /tmp).
- Fingerprint enrollment: `omarchy-setup-security-fingerprint` (lock screen only: with sudo too,
  agents can't use sudo unattended).
- Bluetooth testing: a host-side `bluetoothctl disconnect` disables auto-connect (invalid test);
  connect with `busctl --timeout=90 call org.bluez <dev> org.bluez.Device1 Connect`.
- Hyprland's Lua config: `hyprctl eval '…'` / `hl.dsp.*`, not `hyprctl keyword`.
