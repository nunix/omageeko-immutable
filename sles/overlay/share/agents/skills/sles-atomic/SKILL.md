---
name: sles-atomic
description: >
  REQUIRED on omageeko-immutable systems: Omarchy's Hyprland desktop on SLES 16.1 Immutable
  (transactional, read-only root). Overrides the omageeko skill (written for mutable Tumbleweed)
  and the Arch parts of the omarchy skill wherever they disagree. Triggers: install, remove or
  find software, apps, CLI tools, flatpak, distrobox, podman, mise, zypper, rpm,
  transactional-update, tukit, update, upgrade, omarchy update, omageeko-update, snapshot,
  rollback, snapper, reboot needed, read-only filesystem, /usr, /etc, SELinux, SDDM, greeter,
  boot, services, hardware, Bluetooth, fingerprint, monitors, host profile, the
  omageeko-immutable checkout, and changes meant to survive a reinstall.
---

# sles-atomic Skill

This machine runs **omageeko-immutable**: upstream [Omarchy](https://omarchy.org/) (desktop,
`omarchy` CLI, shell, menus, themes) on **SLES 16.1 Immutable**. The host root is a read-only
btrfs snapshot that changes only through `transactional-update` (a new snapshot, active after a
reboot). Everything else lives in userland. Source: `~/omageeko-immutable`
(github.com/nunix/omageeko-immutable, with the main omageeko repo as the `omageeko/` submodule).

Use it **with the `omarchy` skill** (desktop customization: Hyprland, bar, themes, hooks). The
`omageeko` skill describes the Tumbleweed sibling of this system: read it for background, but
**this skill wins**: no `zypper install` on the host, no vendor repos on the host, no `zypper dup`.

## Topic guides (read the matching one before acting)

- [`apps.md`](apps.md): where software goes, in priority order (userland first)
- [`updates.md`](updates.md): `omageeko-update`, transactional-update, snapshots, rollback, reboots
- [`system.md`](system.md): immutable facts: what is writable, SELinux, SDDM, sudo, logs
- [`hardware.md`](hardware.md): host profiles, layer 05, this laptop's fixes
- [`source.md`](source.md): the checkout, layers, bootstrap, recovery, making changes durable

## Critical rules

1. **The host changes only through transactional-update, and durable host changes go through the
   checkout's layers** (`sles/layers/*`, host profile `host.packages`), which batch them into one
   snapshot. Never `zypper in` on the host: `/usr` is read-only and it fails, or worse, someone
   works around it. A one-off `sudo transactional-update pkg install` needs the user's OK, a
   reboot, and a note that it isn't durable.
2. **Userland first** (`apps.md`): mise, Flathub `--user`, the Tumbleweed box, the Arch box,
   podman. `omarchy pkg add <name>` already picks the right one.
3. **Never edit what the deploy owns:** `~/.local/share/omarchy` (Omarchy tree) and
   `~/.local/share/omageeko` are redeployed by layer 03 from the built RPMs plus
   `sles/overlay`. Change the overlay or a patch in the checkout, then rerun layer 03 user.
4. **Leave alone:** `~/.claude/settings.json` (Vertex AI login), `~/google-cloud-sdk` and its lines
   in `~/.bashrc`, `/etc/sudoers.d/90-omageeko`.
5. **Reboots are the user's call.** Say when one is needed (`snapper list`: a pending default
   snapshot) and why; never reboot from an agent unasked.
6. **SELinux is enforcing.** Find the denial (`sudo ausearch -m avc -ts recent`); never go
   permissive. Files written into `$HOME` from a system context need `restorecon`.
7. **Don't kill by pattern** (`pkill -f`): it matches the agent's own shell. Use exact PIDs.

## System at a glance

| Component | omageeko-immutable |
|---|---|
| Base | SLES 16.1 Immutable (registered with SCC + Package Hub) |
| Host changes | `transactional-update` / `tukit`, one snapshot per run, active after reboot |
| Omarchy | userland tree `~/.local/share/omarchy` (option B) + host RPM `omageeko-sles(-sddm)` |
| Built packages | local repo `/var/lib/omageeko/repo` (`omageeko-local`), seeded from GitHub releases |
| Apps | mise, Flathub `--user`, `omageeko-tw` distrobox, Arch box, podman |
| Login | SDDM, Omarchy's Wayland greeter in Hyprland → "Omarchy" uwsm session |
| Browser | Brave (Flathub, `brave` + `brave-browser.desktop`) |
| Security | SELinux enforcing |

## Quick commands

```bash
omageeko-update --check            # what's pending (host, omageeko layers, apps); changes nothing
omarchy pkg add <name>             # install by Omarchy/Arch name, into userland
snapper list                       # snapshots; '*' booted, '+' default for next boot
~/omageeko-immutable/sles/install.sh --phase verify   # every layer's verify.sh
cat ~/.local/state/omageeko/install-report.txt        # last install/rerun report
```
