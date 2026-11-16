# SLES layer 05 — notes

## 2026-11-16: iPhone USB tethering
- SLES 16.1's kernel has `# CONFIG_USB_IPHETH is not set`: `ipheth` is in neither `kernel-default`
  nor `kernel-default-extra` (Tumbleweed has it in-kernel, so omageeko only adds the userland).
- `packages/ipheth` (layer 02, `local ipheth`): a KMP whose `%prep` copies
  `drivers/net/usb/ipheth.c` out of the `kernel-source` RPM, so the code is the shipped kernel's.
  Output `ipheth-kmp-default` with ksym() Requires and the Apple USB modalias; weak-modules2 keeps
  it across same-kABI kernel updates, `rebuild-on: kernel-default-devel` rebuilds it otherwise.
- Not signed. Fine with Secure Boot off (the ThinkPad); with it on, it needs a MOK key.
- `usbmuxd` (Backports) and `imobiledevice-tools` are installed on every bare-metal profile
  (`COMMON_PACKAGES`), like omageeko's `+usbmuxd`/`+imobiledevice-tools` extras.
- If the phone was plugged in before the snapshot booted, replug it so udev starts usbmuxd.
