# Plan: unattended omageeko install on SLES 16.1 Immutable (CLI and ISO)

Written 2026-11-14 at the end of the first SLES session (KDE-based VM `sles16.1`,
192.168.122.212). To be executed in a new session on a **minimal** SLES 16.1 Immutable
install. Everything below is a plan: no code from it exists yet unless marked ✅.

> **Status 2026-11-14 (end of the second session):** W1–W5 and W8 are implemented (✅ below means
> "exists in the tree"). The first minimal-VM run (`sles16.1-min`) got through the system phase,
> reboot and resume, then lost the VM to an SELinux label bug in layer 04 (fixed; see §9). Decisions
> are fixed (§4): D-1 is now **SDDM**.
> **Status 2026-11-14 (third session):** run 2 on a fresh minimal VM (`sles16.1-min`, 192.168.122.226)
> passes all verify scripts after three fixes (§9 run 2). Next: user test checklist (R9), then R10.
> **Status 2026-11-14 (fourth session):** run 3 on a brand-new VM (`sles16.1-fresh`, 192.168.122.63)
> passed R3–R8 and every verify script in one run, **but the first greeter login failed** (§9 run 3).
> The user does not consider it ready for bare metal yet. §10 is the plan for run 4 and must be done first.
> **Status 2026-11-14 (fourth session, later):** §10 G1–G4 implemented ✅ (`bootstrap.sh`, `tools/publish-repo`,
> `seed-repo github`, `tools/greeter-check`, final reboot, version from `upstream.lock`, `AGENTS.md` + skill).
> Checked on `sles16.1-fresh`: rerun = no seed, no build, no snapshot, no reboot, all verify OK.
> **Run 4 (2026-11-14, `sles16.1-run4`):** bootstrap one-liner only → `greeter: ready` after one bug fix
> (`/var/lib/omageeko` ownership on a pristine machine, §9 run 4). R9 user checklist pending, then bare metal.
> **Run 5 (2026-11-15, `sles16.1-run5`): passed first try, no fixes**, with the greeter hold (§9 run 5). Next: R9 checklist, then bare metal.

Read first: `sles/README.md`, `docs/sles16-immutable-assessment.md`, each layer's `NOTES.md`.

---

## 0. Goal and deliverables

From a minimal SLES 16.1 Immutable system (registered, SSH + passwordless sudo done by the
user), reach the same desktop as the KDE-based VM, with one command:

```bash
~/omageeko/sles/install.sh            # interactive: asks before rebooting
~/omageeko/sles/install.sh --yes --reboot   # unattended: reboots and resumes by itself
```

and, as a second step, a way to produce that system from an ISO without any manual
step (Agama unattended profile, embedded in a remastered ISO).

| # | Deliverable | Where |
|---|---|---|
| D1 | Orchestrator with preflight, phases, resume after reboot, logs, final report | `sles/install.sh` (new) |
| D2 | Layer 00-bootstrap: the desktop base a minimal install lacks (KDE provided it implicitly) | `sles/layers/00-bootstrap/` (new) |
| D3 | `--phase system|user` split for layers 01 and 03 (01b/02 are system-only, 04 user-only) | existing layers |
| D4 | Probe tool: what a host lacks compared with the reference VM | `sles/tools/probe` (new) |
| D5 | Repo seeding: reuse the already built RPMs (saves about 1 h of builds) | `sles/tools/seed-repo` (new) |
| D6 | Agama profile + first-boot script for fully unattended installs | `sles/agama/` (new) |
| D7 | ISO remaster with the profile embedded | `sles/tools/make-iso` (new) |
| D8 | Docs: README, layer NOTES, this plan's results section | `sles/` |

---

## 1. What the first install taught us (inputs for the design)

### 1.1 What KDE provided implicitly
The KDE install brought patterns `kde_plasma`, `x11`, `fonts` (plus `base`, `enhanced_base`,
`immutable_base`, `minimal_base`, `container_runtime_podman`, `selinux`, `x86_64_v3`).
The omageeko layers silently relied on these packages being there (all were installed on
the reference VM; a minimal install will lack many of them — the probe in §5.2 measures it):

| Need | Packages (SLES names) | Used by |
|---|---|---|
| Display manager + greeter | `sddm-qt6` (+ `xorg-x11-server` for its X11 greeter) **or** an alternative (decision D-1) | login, layer 04 default session |
| Audio | `pipewire`, `wireplumber`, `pipewire-pulseaudio`, `pipewire-alsa` | Omarchy audio panel, OSD, pamixer |
| Graphics | `Mesa-dri`, `Mesa-libEGL1`, `Mesa-libGL1`, `libvulkan1`, `libvulkan_lvp`, `xwayland` | Hyprland, quickshell, X11 apps |
| Desktop services | `polkit`, `udisks2`, `upower`, `power-profiles-daemon`, `bluez`, `gvfs`, `dbus-broker`, `NetworkManager` (in `base`) | shell panels, udiskie, Files |
| XDG plumbing | `xdg-user-dirs`, `xdg-utils`, `xdg-desktop-portal`, `xdg-desktop-portal-gtk`, `gsettings-desktop-schemas`, `glib2-tools`, `dconf` | provision-user, theme-set-gnome (gsettings), Flatpak |
| Icons/themes | `adwaita-icon-theme`, `hicolor-icon-theme` | GTK apps, Files, Ghostty |
| Fonts | `google-noto-sans-fonts`, `google-noto-coloremoji-fonts`, `fontconfig` | everything (emoji in bar/menus) |
| Flatpak | `flatpak` | Chromium (layer 01), `omarchy pkg add` Flathub targets |
| Containers | `podman`, `distrobox` (pattern `container_runtime_podman`) | builder, omageeko-twbox, omageeko-box |
| Commands Omarchy scripts call | `ImageMagick`, `socat`, `inotify-tools`, `xsetroot`, `python3` | backgrounds/themes, Hyprland IPC, session restore |
| **Runtime libs of userland bundles** (not RPM deps, nothing pulls them) | `libgtk-4-1`, `libappstream5`, `libgraphene-1_0-0` (+ their own deps) | Ghostty bundle (`ldd` on the reference VM: GTK4 stack, appstream, graphene, X11/xcb, cairo/pango) |
| Package Hub registration | `SUSEConnect -p PackageHub/16.1/x86_64` | Backports + Package Hub repos: most of layer 01, sddm, builder deps |

### 1.2 Ordering constraints found the hard way
1. Host packages only exist **after a reboot** into the new snapshot. Layer 04 needs `jq`/`git`
   (layer 01 host part) and refuses to run while a snapshot is pending ✅.
2. Layer 01's userland part needs `flatpak` (Chromium) — on a minimal install that is a host
   package from 00-bootstrap, so it can only run after the first reboot.
3. The builder needs `podman` *before* anything is built. Select `container_runtime_podman`
   at install time (the plan's prerequisite), otherwise a phase-0 reboot is needed.
4. `omarchy-provision-user` stops at `xdg-settings set default-web-browser chromium.desktop`
   unless Chromium (Flathub + alias) exists → layer 01 user part before layer 04 ✅.
5. GitHub's anonymous API limit (60/h) is used up by mise installs; harmless warnings, but
   the orchestrator should run `mise install` once, not per layer.
6. `transactional-update` exit codes are unreliable → `tu_run` marker ✅; a pending snapshot
   must be continued (`--continue`) ✅ — so all system-phase steps stack into **one** snapshot.
7. tukit hides `/var` → `/etc/tukit.conf.d/omageeko.conf` bind ✅ (created by `ensure_local_repo`).
8. SLES has no `patch` on the host → builder container ✅; no `cpio` guarantee → builder ✅.
9. File capabilities (`/usr/bin/secret-tool`) don't resolve in SLES repos → package names only ✅.
10. Minimal install boots to `multi-user.target` → must set `graphical.target` + DM.

---

## 2. Target architecture

### 2.1 Phases
```
preflight ──► phase system ──► reboot ──► phase user ──► verify ──► report
              (one snapshot)              (no snapshot)
```

| Phase | Steps (in order) | Host change |
|---|---|---|
| preflight | checks in §3.1; no changes | none |
| system | 00-bootstrap host · 01 host (+ host.remove) · 01b build+install · 02 build+install · 03 build + `omageeko-sles` | **one** pending snapshot (each step `tu_run` with `--continue`) |
| reboot | `--reboot`: `systemctl reboot` (resume unit armed); otherwise print instructions and stop | — |
| user | 01 user (mise, xdg-terminal-exec, fonts, Flathub Chromium) · 03 user (Omarchy tree, Ghostty) · 04 (reset + provision + profile + DM default) | none (only `$HOME`, `/var/lib/sddm` or DM equivalent) |
| verify | every layer's `verify.sh`; fails the run on any FAIL | none |
| report | summary: versions, snapshot numbers, timings, host footprint, log path | none |

### 2.2 State and resume
- State file: `/var/lib/omageeko/install.state` (on /var: survives rollbacks, readable by the
  resume unit), key=value lines: `phase=system-done`, `snapshot=<n>`, `user=<name>`,
  `profile=<host profile>`, `started=<iso date>`, per-step `step.<name>=ok <seconds>`.
- `install.sh` with no `--phase` = `auto`: reads the state and continues where it stopped;
  a finished step is skipped (layers are idempotent anyway).
- Resume after reboot (only with `--reboot` or `--unattended`): a **system** unit
  `omageeko-sles-resume.service` written by `install.sh` into `/etc/systemd/system/`
  (in `/etc`, so it survives the snapshot switch — verify: `/etc` changes on the running system
  are carried into new snapshots by tukit):
  ```ini
  [Unit]
  Description=omageeko SLES install: user phase
  After=network-online.target
  Wants=network-online.target
  ConditionPathExists=/var/lib/omageeko/install.state
  [Service]
  Type=oneshot
  User=<user>
  Environment=XDG_RUNTIME_DIR=/run/user/<uid>
  ExecStartPre=+/usr/bin/loginctl enable-linger <user>
  ExecStart=/home/<user>/omageeko/sles/install.sh --phase user --yes
  ExecStartPost=+/usr/bin/loginctl disable-linger <user>
  ExecStartPost=+/usr/bin/systemctl disable omageeko-sles-resume.service
  [Install]
  WantedBy=multi-user.target
  ```
  Linger gives the user a systemd manager, which layer 04 needs (`systemctl --user`).
  Progress is visible with `journalctl -u omageeko-sles-resume -f`.

### 2.3 Logging
`~/.local/state/omageeko/install-<timestamp>.log` (tee of everything) plus the per-package
build logs that already exist (`~/.local/state/omageeko/<layer>/<pkg>.log`). Each step logs
start/end with duration.

### 2.4 Layer interface (D3)
Every layer `install.sh` accepts `--phase system|user|all` (default `all`, unchanged behaviour
when run by hand):

| Layer | system part | user part |
|---|---|---|
| 00-bootstrap (new) | desktop base, graphical target, DM, rebootmgr policy | — |
| 01-base | `host.packages`, `host.remove` | xdg-terminal-exec, mise + tools, fonts, Flatpak + Chromium shim |
| 01b-hyprland | build + install | — |
| 02-build-rpms | build + install | — |
| 03-omarchy | prepare.sh, builds, `omageeko-sles` | Omarchy tree, Ghostty bundle |
| 04-session | — | reset/provision, Files migration, profile, theme, terminal, DM default |

`--phase user` on a system-only layer = no-op; `--phase system` on 04 = no-op.

---

## 3. Work items

### W1 — `sles/install.sh` (orchestrator)
Options: `--phase auto|system|user|verify`, `--yes` (no prompts), `--reboot` (reboot and
resume automatically), `--unattended` (= `--yes --reboot`, used by the Agama init script),
`--profile <name>` (host profile, default `kvm-guest`; a new `minimal-vm` profile may be
added), `--seed <source>` (call W5 first), `--dry-run` (preflight + package resolution only).

#### 3.1 Preflight checks (abort with a clear message; no changes)
1. `/etc/os-release`: `ID=sles`, `VERSION_ID=16.1`, `VARIANT_ID=transactional`.
2. Not root; `sudo -n true` works.
3. Registration: `sudo SUSEConnect -s` shows `SLES 16.1 … Registered` **and**
   `PackageHub 16.1 … Registered`. If Package Hub is missing: offer
   `sudo SUSEConnect -p PackageHub/16.1/x86_64` (with `--yes`: do it).
4. `podman`, `distrobox` present (else: explain `container_runtime_podman`; with `--yes`
   install them in a phase-0 snapshot, reboot, resume).
5. Network: `curl -fsSI https://src.opensuse.org` and `https://github.com`.
6. Disk: `/var` ≥ 20 GiB free (builder image ~1.5 GiB, zypp cache, repo ~0.9 GiB, Tumbleweed
   box ~0.5 GiB); `/home` ≥ 5 GiB (mise ~0.6 GiB, Chromium ~1 GiB, Omarchy tree, Ghostty).
7. No reboot pending from something else (or treat it: continue that snapshot — say so).
8. `~/omageeko` is complete (sles/, packages/, upstream.lock, packages.map, tools/omageeko-bump).
9. `--dry-run`: resolve the whole system phase in one throwaway transaction:
   `sudo transactional-update --non-interactive --drop-if-no-change run zypper --non-interactive install --dry-run --no-recommends <all host packages>`
   (after W5 seeding the omageeko-local packages resolve too) and print what would be installed.

#### 3.2 Phase system
Runs, in order, `00-bootstrap`, `01-base --phase system`, `01b-hyprland`, `02-build-rpms`,
`03-omarchy --phase system`. Afterwards: assert one pending snapshot, list its new packages
(`rpm --root /.snapshots/<n>/snapshot -qa --last | head`), write `phase=system-done`.

#### 3.3 Phase user
Only when no snapshot is pending (i.e. after the reboot): `01-base --phase user`,
`03-omarchy --phase user`, `04-session`. Then verify, report, remove state + resume unit.

#### Acceptance
- From the KDE-based VM (everything installed): `install.sh --yes` changes nothing, creates no
  snapshot, all verify scripts pass (idempotency).
- On the minimal VM: one run (`--unattended`) ends at the SDDM/greeter with the Omarchy session
  preselected; all verify scripts pass; no manual step.

### W2 — `sles/layers/00-bootstrap/`
Files: `install.sh`, `verify.sh`, `host.packages`, `AGENT.md`, `NOTES.md`.

`host.packages` (initial; the probe (W4) on the minimal VM confirms/extends it):
```
# (display manager: SDDM, handled by install.sh — see D-1; the real list is
#  layers/00-bootstrap/host.packages, which also gained desktop-file-utils + pkexec)
# Audio
pipewire
wireplumber
pipewire-pulseaudio
pipewire-alsa
# Graphics
Mesa-dri
Mesa-libEGL1
Mesa-libGL1
libvulkan1
libvulkan_lvp
xwayland
# Desktop services
polkit
udisks2
upower
power-profiles-daemon
bluez
gvfs
# XDG plumbing
xdg-user-dirs
xdg-utils
xdg-desktop-portal
xdg-desktop-portal-gtk
gsettings-desktop-schemas
glib2-tools
dconf
# Icons, fonts
adwaita-icon-theme
hicolor-icon-theme
fontconfig
google-noto-sans-fonts
google-noto-coloremoji-fonts
# Flatpak (Chromium, Flathub targets of omarchy pkg add)
flatpak
# Commands Omarchy scripts call
ImageMagick
socat
inotify-tools
xsetroot
python3
# Runtime libraries of the userland Ghostty bundle (nothing else pulls them)
libgtk-4-1
libappstream5
libgraphene-1_0-0
```
Other actions (all in the same pending snapshot, or on /etc which tukit carries over):
- `systemctl set-default graphical.target`.
- Display manager per D-1 (✅ implemented): `sddm-qt6`, `sddm.service` enabled; Omarchy's greeter
  config + theme are `omageeko-sles-sddm` (layer 03). Layer 04 writes SDDM's last session.
- Services enabled: `bluetooth`, `power-profiles-daemon`, `NetworkManager` (already),
  `udisks2` (socket/dbus activated; nothing to do).
- rebootmgr policy per D-3 (`rebootmgrctl set-strategy off` or `maint-window`).

`verify.sh`: every host package present; `systemctl get-default` = graphical; the DM unit enabled;
`pipewire`/`wireplumber` user units exist; portal files present.

### W3 — `--phase` split (layers 01, 03; no-ops for 01b, 02, 04)
- `01-base/install.sh`: wrap host_install/host_remove in `system`; mise, xdg-terminal-exec,
  `sles_payload` fonts, Flatpak/Chromium in `user`.
- `03-omarchy/install.sh`: prepare.sh + build_lock + `install_from_repo 03 omageeko-sles` in
  `system`; tree deploy + Ghostty in `user`. Note: user part needs the RPMs built (same repo).
- `01b`, `02`: accept and ignore `--phase user`; `04`: accept and ignore `--phase system`.
- verify scripts unchanged.

### W4 — `sles/tools/probe`
Runs on any SLES host (no changes): prints a table of the §1.1 manifest + every layer's
`host.packages` with installed / available / missing, plus the registered products and whether
podman/distrobox/flatpak exist. Used in step R5 of the runbook to finalise W2's list. Also:
`--reference` mode dumps `rpm -qa --qf '%{NAME}\n' | sort` so the KDE VM's list can be diffed
against the minimal one (`sles/tools/probe --reference > /tmp/kde.txt`).

### W5 — `sles/tools/seed-repo <user@source-host>`
Copies `/var/lib/omageeko/repo` (RPMs + repodata + **build stamps only**) from a machine that
already built them (the KDE VM) to this one:
```bash
ssh SRC 'tar -C /var/lib/omageeko -cf - repo' | (sudo mkdir -p /var/lib/omageeko && sudo chown "$USER:" /var/lib/omageeko && tar -C /var/lib/omageeko -xf -)
# per-machine stamps must not travel (they describe the source host's install state):
rm -f /var/lib/omageeko/repo/.stamps/{*-installed,03-userland,03-ghostty,builder-image}
```
`builder-image` is dropped so the builder image is built locally (needed anyway for userland
payload extraction). Build stamps (`01b-*`, `02-*`, `03-<pkg>`) stay, so `build_lock` skips
everything that is identical. The run then only installs. Without seeding: full builds
(≈ 25 min 01b, ≈ 15 min 02, ≈ 10 min 03 incl. Ghostty on 8 vCPUs).

### W6 — Agama unattended profile (`sles/agama/omageeko-sles.jsonnet`)
Jsonnet, parameters at the top (`local registrationCode = std.extVar(...)` is not available at
boot, so the profile is generated per install by W7 or edited by hand):
```jsonnet
{
  product: {
    id: "SLES",
    mode: "immutable",
    registrationCode: "<SCC code>",
    addons: [{ id: "PackageHub" }],           // VERIFY the add-on id in the installer (R1)
  },
  software: {
    patterns: ["container_runtime_podman"],     // minimal + podman/distrobox; VERIFY names
  },
  user: {
    fullName: "<name>", userName: "nunix", password: "<hash>", hashedPassword: true,
  },
  root: { hashedPassword: true, password: "<hash>", sshPublicKey: "<key>" },
  localization: { language: "en_US.UTF-8", keyboard: "<layout>", timezone: "Europe/Zurich" },
  scripts: {
    post: [{
      name: "omageeko-sudo-ssh", chroot: true,
      content: |||
        #!/bin/bash
        set -e
        echo 'nunix ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/90-omageeko
        chmod 440 /etc/sudoers.d/90-omageeko
        install -d -m700 -o nunix -g users /home/nunix/.ssh
        echo '<ssh public key>' > /home/nunix/.ssh/authorized_keys
        chown nunix:users /home/nunix/.ssh/authorized_keys; chmod 600 /home/nunix/.ssh/authorized_keys
        systemctl enable sshd
      |||,
    }],
    init: [{
      name: "omageeko-install",                 // first boot, runs once (agama-scripts service)
      content: |||
        #!/bin/bash
        set -e
        # fetch the checkout: git (if installed) or a tarball served by the build host (W7)
        sudo -u nunix bash -c 'mkdir -p ~/omageeko && curl -fsSL <url>/omageeko.tar.gz | tar -xz -C ~/omageeko'
        sudo -u nunix ~/omageeko/sles/install.sh --unattended
      |||,
    }],
  },
}
```
Open points to verify in R1: exact pattern ids in the immutable product, `hashedPassword`
key names, where `init` scripts run (as root, network up?), whether `post` with `chroot` can
create the user's home files (user exists at that point?). Logs: `/var/log/agama-installation/scripts`.

### W7 — `sles/tools/make-iso`
On the Tumbleweed host (has `xorriso`):
```bash
sles/tools/make-iso --iso ~/Downloads/SLES-16.1-Online-x86_64-GM2.install.iso \
  --profile sles/agama/omageeko-sles.jsonnet --out ~/Downloads/omageeko-sles-16.1.iso \
  [--checkout]   # also embed a tarball of the checkout so first boot needs no host
```
Steps: render the profile (fill code, user, key, password hash), extract the ISO's boot config
(`xorriso -osirrox on -indev IN -extract /boot/grub2/grub.cfg …` — VERIFY the path on the
SLES 16 ISO), add `inst.auto=file:///<embedded path>` (or `inst.auto=label:...` — VERIFY Agama's
syntax for files on the install medium) to the default boot entry, then
`xorriso -indev IN -outdev OUT -map profile.jsonnet /omageeko/profile.jsonnet -map grub.cfg /boot/grub2/grub.cfg -boot_image any replay`.
Simpler variant for VMs (no remaster): serve the profile over HTTP from the host
(`python3 -m http.server -d sles/agama 8000`) and boot the stock ISO with
`inst.auto=http://192.168.122.1:8000/omageeko-sles.jsonnet` (virt-install `--extra-args` needs
`--location`; otherwise type it at the GRUB prompt).
Later option (not in this plan's scope): a KIWI image with the system phase preinstalled.

### W8 — Docs
- `sles/README.md`: "Install from scratch" section (install.sh, prerequisites, seeding, ISO).
- `sles/layers/00-bootstrap/{AGENT,NOTES}.md`; NOTES of 01/03/04 for the phase split.
- Section 9 of this file: results of the minimal-VM run (probe output, timings, surprises).

---

## 4. Decisions needed from the user (ask at the start of the next session)

| # | Decision | Options | Recommendation |
|---|---|---|---|
| D-1 | Display manager | **SDDM, upstream style**: Wayland greeter in Hyprland + Omarchy theme (`omageeko-sles-sddm`) | decided 2026-11-14 (greetd/tuigreet was tried and rejected: not Omarchy's look) |
| D-2 | Keep `foot` as host fallback terminal | **keep** | decided |
| D-3 | rebootmgr nightly auto-reboot | **off** | decided |
| D-4 | First-boot checkout source for the ISO path | **embed tarball in the ISO** | decided |
| D-5 | Host profile for the new VM | **reuse `kvm-guest`** | decided |

---

## 5. Runbook for the next session

### R0 — Prerequisites (user)
- New VM (I create it, R1), minimal SLES 16.1 **Immutable** install: register with SCC, add
  **Package Hub** in the installer if offered, select pattern **Container Runtime (podman)**,
  create user `nunix`, enable SSH, set passwordless sudo, add my key. Note the IP.
- **Set a root password** at install time: it's the only way back in from the console when the
  user account breaks (the SLES guest agent has `guest-exec` disabled and is SELinux-confined).

### R1 — Create the VM (me, on the Tumbleweed host)
Same performance settings as `sles16.1`, with the fixes found later applied from the start:
```bash
PIN=$(for i in $(seq 0 7); do printf 'vcpupin%d.vcpu=%d,vcpupin%d.cpuset=%d,' $i $i $i $((i+8)); done)
virt-install --connect qemu:///system --name sles16.1-min --osinfo sles16.1 \
  --memory 16384 --memorybacking source.type=memfd,access.mode=shared \
  --vcpus 8,sockets=1,dies=1,cores=4,threads=2 \
  --cpu host-passthrough,cache.mode=passthrough,check=none,migratable=off,require=topoext \
  --iothreads 1 --cputune "${PIN}emulatorpin.cpuset=0-7,iothreadpin0.iothread=1,iothreadpin0.cpuset=0-7" \
  --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=yes \
  --tpm model=tpm-crb,backend.type=emulator,backend.version=2.0 \
  --disk path=/var/lib/libvirt/images/sles16.1-min.qcow2,size=100,format=qcow2,bus=virtio,cache=none,io=native,discard=unmap,detect_zeroes=unmap,driver.iothread=1,driver.queues=8 \
  --cdrom /var/lib/libvirt/images/SLES-16.1-Online-x86_64-GM2.install.iso \
  --network network=default,model=virtio,driver.name=vhost,driver.queues=8 \
  --graphics spice,listen=none,gl.enable=yes,rendernode=/dev/dri/renderD128 \
  --video model.type=virtio,model.acceleration.accel3d=yes \
  --channel unix,target.type=virtio,name=org.qemu.guest_agent.0 --rng /dev/urandom --noautoconsole
```
Check: `qemu` command line has `virtio-vga-gl` and `topoext`; if libvirt wrote
`device='virtio-vga'` into `<model>`, remove it (`virsh edit`, as in the first session).
The old VM `sles16.1` stays untouched (seeding source and reference) until R9 passes.
Deleting a test VM: `virsh undefine <vm> --nvram --tpm --storage vda` — **not**
`--remove-all-storage`, which also deletes the shared installer ISO attached as cdrom
(happened once; restored from `~/Downloads`).
Two VMs at 8 vCPU/16 GiB each: stop `sles16.1` while the new one builds if not seeding.

### R2 — Access
`ssh-keyscan`/first ssh to the new IP; `sudo -n true`; record the IP in the memory file.

### R3 — Sync the checkout
`sles/tools/sync-guest nunix@<new-ip>` (no git needed on the guest).

### R4 — Decisions
Decisions are fixed (§4); nothing to ask. W1–W5 + W8 exist ✅ (W6/W7 after R9).

### R5 — Probe
`ssh new '~/omageeko/sles/tools/probe'` (the KDE VM was deleted 2026-11-14; its reference list is
in §9 run 1/2: 1966 packages). Previously: on the KDE VM `probe --reference`; diff the package
lists; finalise `00-bootstrap/host.packages` (add what the stack needs, nothing KDE-only).

### R6 — Seed (optional but recommended)
`sles/tools/seed-repo nunix@192.168.122.226 nunix@<new-ip>` from the Tumbleweed host (relay: the new
VM has no key for the source). Source since 2026-11-14: `sles16.1-min` (run 2, complete repo;
the KDE VM 192.168.122.212 is deleted). Both VMs up. Takes seconds (886 MiB, 147 RPMs, 32 stamps).

### R7 — Dry run
`install.sh --dry-run`: preflight + the one-transaction resolution; review the package list
(size, anything unexpected like a full X11 stack if D-1 ≠ SDDM).

### R8 — Run
`install.sh --unattended` (or phase by phase: `--phase system`, reboot, `--phase user`).
Start it detached on the guest so the reboot doesn't kill the ssh session mid-step:
`ssh vm 'setsid nohup ~/omageeko/sles/install.sh --unattended >/tmp/omageeko-install.out 2>&1 </dev/null &'`.
Watch: `journalctl -u omageeko-sles-resume -f` after the reboot. The unit is `activating` while it
runs (`systemctl show -P ActiveState`), not `active`. **Do not log in at the greeter until it's done.**

### R9 — Acceptance
- All verify scripts pass (00, 01, 01b, 02, 03, 04).
- User test checklist: greeter shows Omarchy session preselected · login · bar/notifications ·
  Super+Enter = Ghostty · Super+Shift+F = Files · Super+Space menu · screensaver
  (`omarchy-launch-screensaver`) · lock (Super+Escape → unlock with password) · audio OSD ·
  Super+Shift+Enter = Chromium (Flathub) · `omarchy pkg add qrencode` → Tumbleweed box · logout.
- Footprint report: number of host packages vs the KDE VM (`rpm -qa | wc -l`), snapshots used.

### R10 — ISO path
Implement W6 + W7; boot a third VM from the remastered ISO with no interaction; the same R9
checklist must pass. Record results in §9.

---

## 6. Test matrix

| Case | Expected |
|---|---|
| Rerun `install.sh` on a finished system | no build, no snapshot, all verify OK |
| Interrupt during phase system (kill, power off) | rerun continues; pending snapshot continued, not duplicated |
| Reboot without `--reboot` | `install.sh` (auto) detects `system-done` and runs the user phase |
| No Package Hub | preflight stops with the SUSEConnect command (or does it with `--yes`) |
| No podman | preflight explains / phase 0 with `--yes` |
| Seeded vs unseeded repo | same result; seeded skips builds |
| ISO install | no interaction from boot to greeter |

## 7. Risks and mitigations
- **Implicit deps missed** → probe + `verify.sh` of 00; Ghostty `ldd` check in 03 already fails loudly.
- **Package Hub add-on id / pattern ids in Agama** → verify in R1/R10 before relying on them.
- **SDDM without X11 on minimal** (if chosen) → greeter fails to start; the DM decision avoids it.
- **Upstream drift** (Tumbleweed pool heads, Ghostty/Zig/xdg-terminal-exec versions) → everything
  is pinned (hyprland.lock, build.lock, spec versions, XTE sha256); bumps are explicit.
- **Rate limits** (GitHub API for mise/xdg-terminal-exec) → one mise install per run; retry.
- **Linger/resume unit** leaves state behind on failure → the unit only runs while
  `install.state` exists; `install.sh --phase verify` shows where it stopped.

## 8. Effort estimate
W1 ~half a session · W2 + W4 small · W3 small · W5 small · W6/W7 needs one ISO round-trip to
verify Agama details. Machine time: full unseeded build ≈ 50 min, seeded ≈ 10 min + downloads.

## 9. Results (fill in during execution)

### Run 1 — 2026-11-14, `sles16.1-min` (192.168.122.79), greetd, seeded repo — VM lost
- Probe diff: minimal (Package Hub + podman pattern) 832 packages vs KDE 1966. Already present on
  minimal: PipeWire, Mesa/Vulkan, polkit, xdg-desktop-portal, glib2-tools/dconf, fontconfig, flatpak,
  podman, distrobox, `graphical.target`. Every 00/01 package available; nothing MISSING.
- Dry run (00+01+01b+02+03): 364 new packages, 195 MiB download, ~645 MiB installed.
- Timings (seeded): 00 35 s · 01 system 16 s · 01b 50 s (incl. builder image) · 02 30 s ·
  03 system 278 s (Ghostty rebuilt by bug 2) · 01 user 39 s · 03 user 16 s · 04 failed.
- Snapshots: each `tu_run --continue` creates a new snapshot on top of the pending one ("Snapshot
  Update of #N"): one *boot*, but #2…#7 in `snapper list`. Harmless; could be cleaned up afterwards.
- `tukit` merges `/etc` changes made inside the transaction back into the running system.
- Surprises / fixes (details in `layers/00-bootstrap/NOTES.md`):
  1. silent exit after the system phase (SIGPIPE + pipefail) · 2. Ghostty stamp name collision ·
  3. resume unit 203/EXEC (SELinux: no exec of `user_home_t` by systemd → `ExecStart=/usr/bin/bash …`) ·
  4. `update-desktop-database` missing → `desktop-file-utils`, `pkexec` added to 00 ·
  5. **`$HOME` relabelled with a /tmp label by layer 04's skel copy → ssh key refused, login failed,
  VM unrecoverable without a root password** → `--no-preserve=context`, per-entry skel copy,
  `restorecon -R $HOME`, label checks in 04 verify · 6. tools use `ssh -o BatchMode=yes`.
- Also affects the KDE VM: its `$HOME` is `user_tmp_t` (`sudo restorecon -R ~` fixes it).

### Run 2 — 2026-11-14, `sles16.1-min` (192.168.122.226, hostname `immusles`), SDDM, seeded repo
- Fresh minimal install (root password set). Probe: 832 packages vs KDE 1966, nothing MISSING,
  `host.packages` unchanged. Dry run: 392 new packages, 229 MiB download, 738 MiB installed
  (SDDM + Qt5/Qt6 greeters + `xdm`; no Xorg server).
- Timings (seeded): 00 49 s · 01 system 15 s · 01b 57 s · 02 24 s · 03 system 274 s (omageeko-sles
  rebuilt for the sddm subpackage, Ghostty rebuilt by the cascade, see 1) · reboot · 01 user 41 s ·
  03 user 15 s · 04 10 s. Layer 04's SELinux fix held: ssh and `$HOME` labels fine throughout.
- Footprint: 1232 host packages (KDE VM: 1966). Snapshots #3–#9 (one per `tu_run --continue`).
- Rerun on the finished system: rc 0, no build, no snapshot (01 user 138 s: mise re-checks tools
  over the network; was 7 s on the run before - GitHub API latency).
- Surprises / fixes:
  1. **Ghostty rebuilt** although seeded: `build_lock` cascades to every later entry and `ghostty`
     came after `omageeko-sles` (which changed). `03-omarchy/build.lock` now lists `ghostty` first.
     (The seeded `03-ghostty` stamp was also stale: the KDE VM still had bug 2's collision.)
  2. **Greeter killed at end of boot** (SIGHUP, `HELPER_AUTH_ERROR`, black screen). `sddm-qt6`
     pulls in `xdm`, whose `%post` points `display-manager.service` at SUSE's
     `display-manager-legacy.service` + `default-displaymanager=sddm`; `target_dm` read that as
     "sddm" so layer 00 never switched to `sddm.service`. The legacy unit only conflicts with
     `getty@tty7`; SDDM uses VT1, `getty@tty1` starts when boot finishes and hangs up VT1. Fixed:
     layer 00 checks the unit link itself, 00 verify FAILs on the legacy unit. Hyprland as the
     greeter compositor under SELinux (`xdm_t`) works: no AVCs.
  3. **Login with an empty user name** ("pam_unix: user unknown"): Omarchy's theme has only a password
     field and uses `userModel.lastUser`, empty on a fresh install (upstream autologins after the
     LUKS unlock). Layer 04 now writes `User=$USER` to `[Last]` in `/var/lib/sddm/state.conf`; 04
     verify checks it.
  4. Vendored `sddm/hyprland.lua` lagged upstream (non-Latin layout handling): refreshed.
  5. `install.sh`: after verify failures the step marks stayed "ok", so a fixed checkout was never
     applied on rerun; and a failing resume unit stayed enabled (rerun at every boot). Now
     `verify_failed` clears step marks + phase and disarms the resume unit.

### Run 3 — 2026-11-14, `sles16.1-fresh` (192.168.122.63, hostname `sleatomic`), SDDM, seeded repo
- Goal: the first try on a new VM has to pass with no fixes. **Passed:** one `install.sh --unattended`
  (21:44:33 → 21:50:54, 6 min 21 s including the reboot), rc 0, "All layers verified", resume unit
  `success` and disarmed, `sddm.service` active through the real unit, no AVC denials since boot.
- Setup: same libvirt XML as `sles16.1-min` (cloned; ISO as boot order 2), minimal Immutable install
  by the user with SCC + Package Hub, podman pattern, root password. Probe: 838 packages, nothing
  MISSING. Seed from `sles16.1-min`: 148 RPMs, 33 stamps, 886 MiB, 4 s. Dry run identical to run 2
  (392 new, 228.9 MiB download, 737.7 MiB installed).
- Timings: 00 51 s · 01 system 16 s · 01b 179 s (builder image built from scratch: the seed removes
  `builder-image` on purpose; no package was built) · 02 26 s · 03 system 4 s (run-2 fix 1 held: no
  Ghostty rebuild) · reboot · 01 user 47 s · 03 user 17 s · 04 10 s.
- Footprint: 1232 host packages (same as run 2; KDE VM 1966). Snapshots #2–#7, booted #7.
- `$HOME` stays `user_home_dir_t` and `authorized_keys` stays `ssh_home_t` after layer 04.
- Cosmetic: during `omarchy-provision-user` (layer 04), mise prints
  `WARN Failed to resolve tool version list … no versions found` once for every lazy tool in
  `omarchy-tools.toml`. Afterwards `mise ls` resolves them all, so the warning is transient and the
  install isn't affected.
- **R9 failed at the first step: login.** The greeter sent an empty user name ("pam_unix: user
  unknown", `Authentication for user "" failed`) and preselected `hyprland.desktop`. Layer 04 wrote
  `state.conf` correctly at 21:50, but the greeter had started at boot (21:49) and reads `lastUser`
  only at startup. `systemctl restart sddm` fixed it and `state.conf` survived the restart. Run 2
  never hit this because its greeter was restarted while debugging. The fix (restart the greeter in
  layer 04 when no seat0 user session exists) is in the tree but **has not been tested on a fresh
  VM**: see §10 G2.
- The report says "omarchy: 4.0.0.alpha". That's misleading: the deployed tree is the v4.5.0 pin
  (`ac2690c`, same as Tumbleweed). Upstream never bumps its `version` file. See §10 G3.

### Run 4 — 2026-11-14, `sles16.1-run4` (192.168.122.21), bootstrap one-liner, GitHub seed
- Fresh minimal install by the user (same R0), passwordless sudo set by the user. Only
  `sles/bootstrap.sh` was run: no sync-guest, no seed VM (`sles16.1-min` deleted).
- **First attempt failed right after preflight:** `install.state: Permission denied`.
  `ensure_local_repo` created `/var/lib/omageeko` as root and only chowned `repo/`; until now the
  manual seed (run before install.sh) chowned the parent as a side effect. Fixed in `9c8fb98`
  (both dirs owned by the user). This is exactly what a pristine machine catches.
- Second attempt (`bootstrap.sh --ref 9c8fb98`): rc 0, no manual step, two reboots by itself,
  install 22:35:53 → 22:39:59, greeter-check 22:40:43: **`greeter: ready (user nunix, session
  Omarchy)`**, all eight checks ok (greeter started after `state.conf`, not killed at end of boot).
  Layer 04 logged "SDDM: greeter restarted to pick up the remembered user": the run-3 bug is
  caught where it happens.
- Timings: seed 10 s (886 MiB release, checksum ok) · 00 50 s · 01 system 16 s · 01b 42 s (builder
  image, nothing built) · 02 24 s · 03 system 5 s · reboot · 01 user 41 s · 03 user 16 s · 04 10 s ·
  final reboot. About 5 minutes from start to greeter.
- Report shows `omarchy: v4.5.0 (ac2690c)`. Footprint 1232 packages, snapshots #2–#7 (booted #7),
  no AVC denials, `$HOME`/`authorized_keys` labels correct, resume and greeter-check units removed.
- Found while preparing run 5 (the user wants bare metal to work first time, with no guessing):
  1. **A greeter appeared halfway through the install.** After the first reboot SDDM came up while the
     user phase was still running (~2 min, empty remembered user): on bare metal a person logs in there and fails or
     lands in a half-installed session. Now `arm_resume` adds an sddm drop-in
     `ConditionPathExists=!/var/lib/omageeko/greeter-hold` and creates the hold; the resume unit
     prints to the console and removes the hold when it stops (success or failure). Tested on
     run 4's VM: sddm "start condition unmet", boot `running`, progress visible on VT1
     (`/dev/vcs1`), greeter starts once the hold is removed. A condition, not an ordering, so layer
     04 can't deadlock on sddm.
  2. **sudo with a password was untested** (run 4 had NOPASSWD set by the user). Tested through a pty:
     one prompt, then `90-omageeko` (440, `etc_t`) and NOPASSWD work. The prompt was
     `[sudo] password for nunix` (wheel rule) although SLES defaults to `targetpw`; the message now
     says to type the password the prompt names.

### Run 5 — 2026-11-15, `sles16.1-run5` (192.168.122.71), bootstrap one-liner from the console
- Fresh minimal install by the user. The user ran the one-liner on the VM console before I was
  connected. Code at `5e1a117` (greeter hold). **Passed first try, no fixes, no manual step.**
- After the first reboot: `sddm` inactive with the hold in place (no greeter mid-install); the resume
  banner and progress went to the console. After the final reboot: `greeter: ready (user nunix,
  session Omarchy)`; the user was already logged in on seat0 when the check ran.
- Install 10:49:48 → 10:54:21, greeter check 10:55:07. Timings: seed 19 s · 00 53 s · 01 system
  17 s · 01b 46 s · 02 26 s · 03 system 5 s · reboot · 01 user 48 s · 03 user 16 s · 04 10 s.
- Footprint 1232 packages, snapshot #7, no AVC denials, labels correct, units cleaned up.
- Not exercised in this run: bootstrap's sudo setup (the user had already put a NOPASSWD rule in
  `/etc/sudoers.d/nunix`). That path was tested separately through a pty on run 4's VM.
- Cosmetic: an empty `/var/lib/omageeko/repo.before-seed.*` is left behind (the empty repo dir
  that `ensure_local_repo` created, moved aside by the seed). Harmless.
- **R9 found a major bug: no working browser.** Super+Shift+B did nothing and `git` HTTPS login
  couldn't open the device page. Cause: the flags symlink in the Chromium sandbox dir collided with
  Flatpak 1.16's xdg-config mount (bwrap error), so Chromium died at start (layer 01 NOTES). The
  user asked for **Brave**: Flathub `com.brave.Browser` with a `brave` command +
  `brave-browser.desktop` alias (layer 01, generic for Flathub browsers, no symlink), default
  browser + `brave-flags.conf` from the host profile file `browser` (layer 04), dock pin. Verify now
  starts each browser sandbox and checks `omarchy-cmd-default-browser`. Also found: stage copies
  leaked `user_tmp_t` through xattrs (`--no-preserve=context,xattr` now). Tested on run 5's VM by
  rerunning layers 01/03/04: verify all OK, zero tmp labels without restorecon, Super+Shift+B's
  command opens Brave with Omarchy's flags, `xdg-open https://github.com/login/device` opens Brave.
  Not yet tested in a fresh one-pass install.
- **Bare-metal profile (2026-11-15, after R9):** the target is the same laptop as the Tumbleweed host
  (ThinkPad P14s Gen 4 AMD, DMI `21K6S0A00C`). New host profile `sles/hosts/21K6S0A00C` from the live
  config (3-screen desk layout, keybinds incl. carousel/column swap, touchpad, bar, G9 wake kick,
  lumon/ghostty/brave) plus `host.packages`; `install.sh` picks the profile from the DMI product name.
  New SLES **layer 05-hardware**: profile packages (fprintd, fprintd-pam, libfprint, bolt, fwupd,
  sof-firmware, ddcutil), `omageeko-hardware` (already built with omageeko), `bluez-tools` (new in
  02's lock: SLES has no bt-agent, so Bluetooth pairing would loop, as it did on Tumbleweed),
  ppd + BLE privacy timer enabled, monitor wake kick for the user. Firmware: a minimal SLES already
  has kernel-firmware-all + ucode-amd. Rehearsed on run 5's VM with `OMAGEEKO_HOST_PROFILE=21K6S0A00C`:
  bluez-tools built in 19 s, one snapshot, verify all OK after the reboot, rerun = no snapshot, no
  failed units; the profile's Hyprland config verifies like the live one.
- **R9: the matrix screensaver drew boxes** ("?" diamonds): tte's matrix effect uses half-width
  katakana and kanji, and no installed font covered them. Layer 00 adds `google-noto-sans-jp-fonts`
  (JP only, not the whole CJK meta package); on run 5 U+FF71/FF8A/65E5/30FB resolve to Noto Sans CJK JP.

### Run 6 — 2026-11-15, `sles16.1-run6` (192.168.122.125), SMBIOS product `21K6S0A00C`
- VM with the ThinkPad's DMI product name: the plain bootstrap picked the ThinkPad profile by itself
  (`host profile: 21K6S0A00C (machine: 21K6S0A00C, virtual)`). Seed (new release with bluez-tools)
  36 s, 00 52 s, 01 17 s, 01b 45 s, 02 24 s, 03 5 s, **05 system 22 s** (profile packages,
  omageeko-hardware, bluez-tools, units), greeter held after the reboot, 01 user 46 s (Brave),
  03 user 17 s.
- **Failed in layer 04:** `omarchy-provision-user` exit 2. It ends with
  `xdg-settings set default-web-browser chromium.desktop`; with Brave instead of Chromium there's no
  chromium.desktop on a fresh install (run 5 still had Chromium, which hid it). Fix: tree patch
  `tree-20-provision-browser-from-profile` (uses `$OMAGEEKO_BROWSER_DESKTOP`, exported by layer 04
  from the host profile; never aborts) + `finish()` starts the greeter whenever it isn't running
  (a manual rerun after a failed resume left the machine at the text console).
- Recovery on the same VM (as on bare metal: rerun the bootstrap one-liner): the rerun skipped layer
  03 (marked ok), so 04 failed again on the old tree. Fix: a failed step clears the step marks (and
  disarms the resume unit); the next rerun repeated the phase. Its verify then found two more gaps,
  both fixed: no greeter when rerunning after a failed resume (the user phase now starts it unless
  held), and `bt-agent.service` (user) only enabled by Omarchy at first login (layer 05 enables it).
  Final rerun: all layers verified, `greeter: ready`, no extra snapshot, no failed units.
  Run 6 needed fixes, so the one-pass proof is run 7.

---

## 10. Plan for run 4: ready for bare metal (written 2026-11-14 after run 3; G1–G4 implemented ✅)

The user's objections after run 3, and what each one means:

1. *"The code is on GitHub, so why did we need `sles16.1-min` as a source?"* It wasn't a source of
   code. It was a **cache of built RPMs**: layers 01b/02/03 rebuild Hyprland, quickshell, Ghostty,
   etc. locally (~50 min). Nothing publishes those binaries, so the only shortcut was copying another
   machine's repo. A bare-metal install must not depend on a VM that happens to exist.
2. *"The login didn't work after the first system configuration."* On bare metal that means a TTY
   and ssh just to recover. The install must end at a working greeter, and the run must prove it.
3. *"Omarchy says 4.0.0, we are on 4.5."* The code is already v4.5.0 (see §9 run 3), but the report
   must say so. The 4.5 theme intro (`shell/services/BackgroundIntro.qml`,
   `omarchy-theme-bg-boot-intro`) must be seen at first login, so it becomes an acceptance item.
4. One entry point: a script anyone can run, plus an agent-ready runbook in the repo.

### G1 — Published binary repo (replaces the seed VM)
- `sles/tools/publish-repo`: run on any machine with a finished install. It packs
  `/var/lib/omageeko/repo` (RPMs + `.stamps`, minus the per-machine stamps `seed-repo` already
  strips), writes `SHA256SUMS`, and uploads one asset to a GitHub release of omageeko-immutable
  (`gh release upload`). The tag is a **lock hash**: `repo-<sha256 of hyprland.lock + 02/03
  build.lock + specs>[:12]`. Same locks mean the same binaries, so the tag says exactly which
  checkout it fits.
- `install.sh --seed github` (**the default**): compute the lock hash, download the matching
  release asset, check `SHA256SUMS`, unpack, and strip per-machine stamps (shared with `seed-repo`).
  No matching release (e.g. right after a bump) → warn and build locally, as today. `--seed none`
  forces a local build. `--seed user@host` keeps the current relay.
- Integrity: download over HTTPS from the repo's own releases, plus the checksum. The RPMs are
  unsigned today, and the local repo is already trusted (`gpgcheck` off for `omageeko-local`).
  Signing is a later step (R10/ISO), and stays recorded as a risk in §7.
- Bump workflow: `bump.sh` → build on the Tumbleweed-side VM (or bare metal) → `publish-repo`. The
  publisher doesn't need SCC; builds stay in the BCI builder as now.
- **Test matrix additions:** a fresh VM with `--seed github` (expected: no builds, ~7 min); a fresh
  VM with `--seed none`, timed once, so the bare-metal fallback is known to work end to end.

### G2 — The greeter works on the first boot
- Layer 04 restarts `sddm.service` after writing `state.conf`, only when seat0 has no `user`
  session (done in the tree, untested).
- Defence in depth: `--unattended` ends with **one final reboot** after verify passes
  (`--no-final-reboot` to skip). On bare metal that is what a person does anyway, and it proves the
  whole boot path: snapshot, `sddm.service` on VT1, `getty@tty1` not stealing it, remembered user.
  After the reboot, a one-shot check (in the resume unit's last step) logs `greeter: ready (user
  nunix, session omarchy)` or FAIL into the install log.
- 04 verify: FAIL when the greeter is running without a seat0 user session and started *before*
  the `state.conf` mtime (exactly run 3's failure).
- Acceptance (R9): the first password typed at the greeter logs in. No restart, no ssh.

### G3 — Version shown and checked
- Report and layer 03 print the release and commit from `upstream.lock`
  (`Omarchy v4.5.0 (ac2690c)`), not upstream's stale `version` file.
- 03 verify: FAIL when the deployed `upstream-commit` differs from `upstream.lock`'s `commit`.
- R9 checklist gains: **the theme intro plays at first login**, and `omarchy-theme-set <other
  theme>` plays the switch intro. If it doesn't, look first at QtMultimedia/ffmpeg in the host set
  (`qt6-multimedia`, `ffmpeg-7` are pulled in today by dependencies, not listed in 00).

### G4 — One entry point: script first, agent runbook on top
Recommendation: **the script is the product; the agent skill is how an operator (or Claude) drives
and repairs it**. The skill must never duplicate install logic: it calls the script, watches it,
and maps failures to known fixes.
- `sles/bootstrap.sh` (curl-able; the guest has no git):
  `curl -fsSL https://raw.githubusercontent.com/nunix/omageeko-immutable/main/sles/bootstrap.sh | bash -s -- [--ref <tag>]`
  1. Checks: SLES 16.1 transactional, not root, sudo works (asks once, no NOPASSWD needed).
  2. Downloads the omageeko-immutable tarball at `<ref>` and the omageeko submodule tarball at the
     commit pinned in that ref (GitHub tarballs don't include submodules; the pin comes from the
     contents API: `repos/nunix/omageeko-immutable/contents/omageeko?ref=<ref>` → `sha`).
  3. Unpacks to `~/omageeko-immutable`, writes `.omageeko-commit` (as `sync-guest` does), then runs
     `install.sh --unattended --seed github`, detached, with the log path printed.
  4. Works from the TTY on bare metal: survives the reboot through the existing resume unit.
- `.claude/skills/install-omageeko-immutable/SKILL.md` + `AGENTS.md` at the repo root
  (`CLAUDE.md` → symlink), so a session started in this repo knows the rules (userland first, no
  `zypper in` on the host, decisions D-1…D-5) and the runbook:
  inputs (target `user@host`, or local) → access check (ssh key, `sudo -n`) → probe → bootstrap or
  sync-guest → launch detached → monitor the install log and the resume unit → on failure, look up
  the known-failure table (built from §9 and the layers' `NOTES.md`: SELinux labels, legacy DM unit,
  empty greeter user, builder SCC secret, Package Hub missing) → re-run → record the run in §9.
  Includes the monitor command used in run 3.

### Run 4 runbook (fresh VM, then bare metal)
1. Implement G1–G4. Publish the repo from `sles16.1-fresh` (it has every RPM of the current locks).
2. Delete `sles16.1-min` (no longer a seed source). Keep `sles16.1-fresh` until run 4 passes.
3. New VM, minimal install exactly as R0. **Do not touch it beyond ssh key and sudo.**
4. On the guest, from a TTY or ssh: the bootstrap one-liner, nothing else. Claude only watches.
5. Pass = verify all OK + final reboot + greeter ready + first login works + theme intro plays + R9
   checklist + footprint (expected ~1232 packages).
6. Optional, same day: a second fresh VM with `--seed none`, to time the full local build.
7. Bare metal: same one-liner with `OMAGEEKO_HOST_PROFILE` for the machine (new host profile next to
   `kvm-guest`), and the ISO path (R10) after that.
