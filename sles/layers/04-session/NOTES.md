# SLES layer 04 — notes

Status: **applied and verified 2026-11-13**; first login pending.

- Same user reset as TW layer 04, from `~/.local/share/omageeko/skel` (rewritten by layer 03):
  backup once, copy defaults, mark migrations done, `omarchy-provision-user --force`.
- Needs layer 01's host tools active (jq, git): refuses to run while a snapshot is pending.
- Host profile `sles/hosts/kvm-guest`: bindings.lua + input.lua from hosts/21K6S0A00C, the
  reference machine's shell.json, theme `lumon`. Not monitors.lua (VM display).
- SDDM (kept, not lightdm): `[Last] Session=/usr/share/wayland-sessions/omarchy.desktop` in
  `/var/lib/sddm/state.conf` (outside snapshots).
- provision-user stops at `xdg-settings set default-web-browser chromium.desktop` unless
  Chromium exists; layer 01 provides it (Flathub + alias).
- `Hyprland --verify-config` reports `startup-cursor.lua:79: hl.env ... must be a string`: it
  needs a running instance (`HYPRLAND_INSTANCE_SIGNATURE`); same on Tumbleweed, not a config error.

## 2026-11-14: skel copy and SELinux labels
`cp -af "$SKEL/." "$HOME/"` also applied the skel directory's mode/owner/**SELinux label** to `$HOME`
(the skel comes from a `/tmp` stage: `user_tmp_t` on the KDE VM, worse from a system unit — it locked
the minimal VM out of ssh and the greeter). Now the skel's entries are copied one by one with
`--no-preserve=context`; verify.sh checks `$HOME` (`user_home_dir_t`), `~/.ssh` (`ssh_home_t`) and that
nothing under `$HOME` carries a `*_tmp_t` label. Fix an affected host with `sudo restorecon -R $HOME`.
`--phase system` is a no-op.
