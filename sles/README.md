# omageeko — SLES 16.1 Immutable target

omageeko's Tumbleweed layers (`omageeko/layers/`, in the submodule) assume a mutable root. This directory holds the
counterpart for **SLES 16.1 Immutable** (`VARIANT_ID=transactional`), where the host only
changes through `transactional-update` snapshots. Assessment and decisions:
[`docs/sles16-immutable-assessment.md`](../docs/sles16-immutable-assessment.md).

## Principles

- **Userland first:** mise, Flatpak (user), distrobox, podman. The host only gets what needs system access.
- **One snapshot per layer run**, and no snapshot when nothing changed.
- **Builders are containers** (SLES BCI + the host's SCC registration as podman secrets). No toolchains on the host.
- Omarchy itself lives in `~/.local/share/omarchy` (layer 03 option B).

## Layers

| Layer | Status | What | Host footprint |
|---|---|---|---|
| [`00-bootstrap`](layers/00-bootstrap/) | new 2026-11-14 | desktop base a minimal install lacks (audio, graphics, services, portals, fonts, Flatpak); SDDM (Omarchy Wayland greeter + theme via `omageeko-sles-sddm`); graphical target; rebootmgr off | ~40 packages + deps (minimal installs only) |
| [`01-base`](layers/01-base/) | verified | 17 host packages (terminal, Wayland helpers, jq/git, keyring, udiskie); mise + 16 CLI tools (incl. herdr); fonts; Flathub Chromium | 17 packages |
| [`01b-hyprland`](layers/01b-hyprland/) | verified | Hyprland 0.57.2 stack rebuilt from openSUSE's packaging | 25 packages, 3 replaced (xkbcommon) |
| [`02-build-rpms`](layers/02-build-rpms/) | verified | quickshell, owe/owe-lockfeed, titlebars plugin, share picker, ttfx, Files (folio) | 7 packages + deps |
| [`03-omarchy`](layers/03-omarchy/) | verified | Omarchy in `~/.local/share/omarchy` (option B) + SLES overlay; Ghostty bundle in `~/.local/opt/ghostty` (default terminal) | `omageeko-sles` (session entry, lock PAM) + `omageeko-sles-sddm` (greeter config, theme) |
| [`04-session`](layers/04-session/) | verified, session in use | user reset + provisioning, host profile, SDDM default | none |
| 05 hardware | n/a in the VM | lock PAM is in `omageeko-sles`; ppd ships with SLES | — |
| 08 system | deferred | zram/oomd tuning; `omageeko-system` needs scx (not in SLES) | — |

Order: 00 → 01 → 01b → 02 → 03 (their host changes stack into one pending snapshot) → reboot →
01 user part → 03 user part → 04. Layers take `--phase system|user|all` (default all).

## Install from scratch

Prerequisites: SLES 16.1 **Immutable**, minimal, registered with SCC, **Package Hub** added,
pattern **Container Runtime (podman)**, a normal user with passwordless sudo. Then:

```bash
sles/tools/sync-guest user@vm                 # from a machine with the checkout (the VM needs no git)
sles/tools/seed-repo user@built-host user@vm  # optional: reuse built RPMs (skips ~50 min of builds)
ssh user@vm '~/omageeko-immutable/sles/install.sh --dry-run'      # preflight + package resolution, no changes
ssh user@vm '~/omageeko-immutable/sles/install.sh --unattended'   # system phase, reboot, user phase at boot
```

`install.sh` runs preflight (product, registration, podman, network, disk, checkout), the
**system phase** (layers 00, 01, 01b, 02, 03 into one snapshot), reboots (`--reboot`/`--unattended`;
otherwise it stops and a rerun continues), then the **user phase** (01, 03, 04 user parts) from
`omageeko-sles-resume.service`, all `verify.sh`, and writes a report
(`~/.local/state/omageeko/install-report.txt`). Follow a resumed run with
`journalctl -u omageeko-sles-resume -f`. `sles/tools/probe` shows what a host lacks without changing
anything. Plan, decisions and results: [PLAN-install.md](PLAN-install.md).

## Layout

```
sles/builder/Containerfile      the SLES BCI builder image (all layers)
sles/lib/common.sh              helpers (SCC secrets, local repo + tukit bind, tu_run, lock builds, installs)
sles/lib/build-pkg.sh           builds one pool package or local spec in the builder
sles/lib/userland.sh            option B: unpack RPMs, deploy the Omarchy tree into $HOME
sles/overlay/                   SLES replacements laid over the userland tree (pkg-add, update, twbox)
sles/hosts/<profile>/           per-machine user files + theme (layer 04)
sles/install.sh                 orchestrator: preflight, phases, resume after reboot, verify, report
sles/tools/sync-guest           copy the checkout to a guest without git
sles/tools/seed-repo            copy built RPMs + build stamps from another host
sles/tools/probe                what this host lacks (read-only); --reference dumps the package list
sles/layers/NN-name/            install.sh, verify.sh, AGENT.md, NOTES.md (+ layer-specific files)
/var/lib/omageeko/repo          local RPM repo (zypper alias omageeko-local), bind-mounted into transactions
```

The guest doesn't need git: `sles/tools/sync-guest <user@host>`.
