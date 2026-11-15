# System facts (SLES 16.1 Immutable)

## What is writable

| Path | Writable? | Notes |
|---|---|---|
| `/usr`, `/` | no | read-only snapshot; changes only via transactional-update |
| `/etc` | yes | persists across snapshots; vendor defaults in `/usr/etc` |
| `/var` | yes | not in root snapshots: Flatpak, containers, `/var/lib/omageeko` |
| `/home` | yes | the user's data, mise, `~/.local/share/omarchy` |
| `/opt`, `/usr/local` | subvolumes | avoid; prefer userland paths |

## Login and session

- SDDM (`display-manager.service` → `sddm.service`, not xdm's legacy unit: that one lets
  getty@tty1 kill the greeter), Omarchy's Wayland greeter running in Hyprland, theme `omarchy`
  (`omageeko-sles-sddm`). The theme has no user field: it logs in as `[Last] User=` in
  `/var/lib/sddm/state.conf` (layer 04 writes it).
- `sles/tools/greeter-check` tells whether the machine is at a greeter that will log the user in.
- The session is uwsm: `~/.config/uwsm/env.d/*`; Hyprland logs: `journalctl --user -u 'wayland-wm*'`.

## Privilege

`/etc/sudoers.d/90-omageeko` gives the user passwordless sudo (the install's resume unit needs it).
On SLES, sudo's prompt may ask for the user's or root's password depending on the install.

## SELinux (enforcing)

- systemd can't exec `user_home_t` files: units run `/usr/bin/bash <script>`.
- `cp -a --no-preserve=context` still copies the label xattr; use `--no-preserve=context,xattr`.
- Wrong label on `$HOME` breaks sshd and logins: `sudo restorecon -R ~` (needs the root console
  if the user can't log in: keep a root password).

## Containers and registration

- Podman rootless; the builders run in SLES BCI containers with SCC passed as podman secrets.
- `SUSEConnect -s` shows registrations; SLES + Package Hub must be registered.
