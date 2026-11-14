# omageeko on SLES 16.1 Immutable — assessment

Assessed 2026-11-13 on a KVM guest (`sles16.1`, 192.168.122.212, hostname `immusles`):
SLES 16.1 GM2 Online ISO, "Immutable" install with KDE. Target-specific code lives in
[`sles/`](../sles/README.md).

## Decisions (2026-11-13)

- **Userland first.** Anything that doesn't need system access goes to mise, Flatpak (user),
  distrobox or podman. The host only gets what must be system-wide, via `transactional-update`.
- **Layer 03 = option B:** Omarchy lives in `~/.local/share/omarchy` (`$OMARCHY_PATH`) and updates
  without a reboot; only a minimal system RPM (session file, uwsm env.d, PAM, units) goes on the host.
- **Hyprland = SLES layer 01b:** built in a dedicated container (`omageeko-sles-builder`, SLES
  BCI 16.1) from openSUSE's own packaging, installed in one transaction. Part of every update.
- Passwordless sudo for the user is set up in the guest (sudoers.d).

## What SLES 16.1 Immutable gives by default

| Area | Default |
|---|---|
| OS | SLES 16.1 "Enterprise Server (Immutable)" (`VARIANT_ID=transactional`), kernel 6.12. Read-only btrfs root, changes via `transactional-update`. `/etc` writable subvolume, `/home` outside root snapshots, `/var` its own partition. |
| Updates | `transactional-update.timer` **and `rebootmgr` enabled: nightly update + automatic reboot**. snapper timeline/cleanup timers. |
| Boot | GRUB2 + shim, Secure Boot on. No systemd-boot/sdbootutil. |
| Security | SELinux enforcing, firewalld active. |
| Repos | SLES product + Package Hub + Backports (467 installed packages come from Package Hub, incl. all of KDE). NVIDIA repos present, disabled. |
| Desktop | KDE Plasma 6.6 (Wayland), SDDM, Firefox, Konsole, Dolphin. |
| Containers | podman 5.8 rootless (cgroup v2, overlay, netavark), distrobox 1.8.2.5, subuid/subgid set. flatpak installed, **no remotes**. |
| Base | pipewire, wireplumber, NetworkManager, bluez, chrony, qemu-guest-agent. |
| CLI | Almost nothing: **no git, no gcc**; curl, wget, vim. |

### Transactions and `/var`
`tukit` hides `/var` inside a transaction, so a `dir:` repo in `/var/lib/omageeko/repo` is invisible
to `transactional-update pkg install`. Fix: `/etc/tukit.conf.d/omageeko.conf` with
`BINDDIRS["omageeko-repo"]="/var/lib/omageeko"` (read-only use, so the "not rolled back" caveat in
tukit.conf doesn't matter). The drop-in directory doesn't exist by default.

### SCC inside containers
BCI images only see the public `SLE_BCI` repo. Passing the host's registration as podman secrets
(`/run/secrets/SCCcredentials`, `/run/secrets/SUSEConnect`) plus `ADDITIONAL_MODULES=PackageHub` lets
`container-suseconnect` add SLES product, Package Hub and Backports, rootless.

## Omarchy components in SLES repos

- **Missing:** hyprland, uwsm, quickshell, walker/elephant/swayosd (not used by quattro anyway),
  hyprsunset, ghostty, mise, satty, cliphist, impala, wiremix, scx.
- **Backports, too old for quattro:** hypridle, hyprlock, hyprpaper, xdg-desktop-portal-hyprland 1.3.5,
  waybar 0.11, mako, alacritty 0.13, foot, kitty, chromium.
- **Available:** CLI/TUI tools (btop, fzf, eza, bat, ripgrep, fd, zoxide, starship, gum, lazygit,
  neovim, tmux, jq), Wayland helpers (grim, slurp, wl-clipboard, playerctl, brightnessctl), plymouth,
  power-profiles-daemon, fprintd, zram-generator, systemd-experimental, lightdm.
- **Too old for the Hyprland stack** (rebuilt in 01b): wayland-protocols 1.47 (needs 1.49),
  libxkbcommon 1.8.0 (needs 1.11); missing: sdbus-c++ 2, glaze, lua 5.5.

## Layer comparison

Placement: **U** userland (mise / `~/.local`) · **F** Flatpak (user) · **DB** distrobox · **P** podman · **H** host via `transactional-update` (reboot).

| Layer | omageeko on Tumbleweed | Gap on SLES Immutable | SLES approach | Where |
|---|---|---|---|---|
| 00 bootstrap | git + podman, Packman, local repo, TW builder image | no git; no Packman; builders must match SLES | `git-core` on host; SLES BCI builder images with SCC secrets; repo on `/var` + tukit bind; codecs come with Flatpak runtimes | H (git), **P** |
| **01b hyprland** (new) | TW ships Hyprland | whole stack missing / too old | rebuild pinned `src.opensuse.org/pool/*` packaging in `omageeko-sles-builder`; one transaction; rerun on update | **P** → H |
| 01 base packages | CLI/TUI, dev libs, Wayland helpers, fonts | older tools; toolchains would land on host | CLI via **mise**; dev toolchains/`-devel` in a **Tumbleweed distrobox** (reuses packages.map names); fonts in `~/.local/share/fonts`; only desktop-critical Wayland helpers on host | **U**, **DB**, H |
| 02 build RPMs | quickshell, fonts, owe, omasnap, aether… | none on SLES | desktop-critical (quickshell, titlebars, share-picker) as host RPMs from a SLES builder (titlebars rebuilds with 01b's hyprland-devel); fonts → user; apps → DB/U | **P** → H, U, DB |
| 03 omarchy core | RPMs in `/usr/share/omarchy` | RPM update = snapshot + reboot | **option B (chosen):** `~/.local/share/omarchy` + minimal system RPM | **U** (+ H) |
| 04 session | omarchy.desktop, uwsm env.d, lightdm, chromium | SDDM fine; chromium only in Backports | keep SDDM + Plasma fallback; session/uwsm/PAM in the minimal RPM; browser from Flathub | H (min), **F** |
| 05 hardware | bluez-tools, fprintd, ppd, host files | bluez-tools missing; VM has no BT/fingerprint/GPU | mostly untestable in the VM; bluez-tools from the SLES builder; host files stay user files | H, U |
| 06 shell/menu | `omarchy pkg add` → zypper / Flathub / Arch box | zypper on host = reboot per install | SLES map column defaulting to `@flatpak` / `@box` / `@mise`; `transactional-update` last resort; flathub user remote; keep the Arch box | **F**, **DB**, U |
| 07 login/boot | systemd-boot + sdbootutil + plymouth | GRUB2 + shim + Secure Boot | plymouth theme only; GRUB + snapper already boot snapshots | H |
| 08 system | zram, oomd, scx, podman, firewalld, printing | no scx; podman/firewalld preconfigured | zram + oomd via the system RPM; drop scx; Docker workloads on rootless podman (`podman-docker`), lazydocker via mise | H, U |
| updates | `omageeko-update` (`zypper dup` + rebuild + gates) | nightly auto update + auto reboot | wrap `transactional-update` + 01b `bump.sh`/`install.sh` + `mise up` + `flatpak update --user` + `distrobox upgrade --all`; disable rebootmgr auto-reboot on a desktop | H, U |
| apps | RPM / Flathub / Arch box | no Packman codecs | Flatpak first (LibreOffice, mpv, Obsidian, Signal, Spotify, 1Password); Dolphin instead of Nautilus | **F** |

## Open items

1. 3D acceleration for the VM (virtio-gpu with GL via SPICE or egl-headless); Hyprland won't start on the current 2D display.
2. Decide on rebootmgr's nightly auto-reboot.
3. Option B means removing omageeko's hard-coded `/usr/share/omarchy` assumptions (overlay, spec, menu-transform).
