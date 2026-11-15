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
pattern **Container Runtime (podman)**, a normal user in `wheel`. Set a root password: it's the way
back in from the console if the user account ever breaks. On the machine, as that user (from the
console or ssh; no git needed):

```bash
curl -fsSLo /tmp/omageeko-bootstrap.sh https://raw.githubusercontent.com/nunix/omageeko-immutable/main/sles/bootstrap.sh
bash /tmp/omageeko-bootstrap.sh            # --profile <name> on real hardware, --ref <tag> to pin
```

`bootstrap.sh` sets up passwordless sudo if needed (asks once for the password sudo's prompt names:
yours, or root's on some installs), downloads this repo and the pinned
omageeko submodule to `~/omageeko-immutable`, and starts `install.sh --unattended`:

1. **preflight**: product, registration (adds Package Hub with `--yes`), podman, network, disk, checkout
2. **seed**: prebuilt RPMs from the GitHub release that matches the locks (`--seed github`, default;
   `--seed none` builds everything locally, ~50 min; `--seed user@host` copies another machine's repo)
3. **system phase**: layers 00, 01, 01b, 02, 03 into one pending snapshot, then a reboot
4. **user phase** at boot (`omageeko-sles-resume.service`): 01, 03, 04 user parts, every
   `verify.sh`, the report (`~/.local/state/omageeko/install-report.txt`). The greeter is held
   back meanwhile (a text console shows the progress), so nobody logs in to a half-installed session
5. **final reboot** into the greeter; `tools/greeter-check` writes
   `/var/lib/omageeko/greeter-check.txt`, ending in `greeter: ready ...`. Then log in.

Follow it: `journalctl -u omageeko-sles-resume -f` after the first reboot. Rerunning `install.sh`
on a finished system builds nothing, makes no snapshot and doesn't reboot.

From another machine with the checkout instead (development): `sles/tools/sync-guest user@vm`, then
`ssh user@vm '~/omageeko-immutable/sles/install.sh --dry-run'` and `--unattended`.
`sles/tools/probe` shows what a host lacks without changing anything. After a bump, publish the
new binaries from a machine that built them: `sles/tools/publish-repo user@host`. Driving an
install with an agent: [`AGENTS.md`](../AGENTS.md) and the skill in
`.claude/skills/install-omageeko-immutable/`. Plan, decisions and results:
[PLAN-install.md](PLAN-install.md).

## Layout

```
sles/builder/Containerfile      the SLES BCI builder image (all layers)
sles/lib/common.sh              helpers (SCC secrets, local repo + tukit bind, tu_run, lock builds, installs)
sles/lib/build-pkg.sh           builds one pool package or local spec in the builder
sles/lib/userland.sh            option B: unpack RPMs, deploy the Omarchy tree into $HOME
sles/overlay/                   SLES replacements laid over the userland tree (pkg-add, update, twbox)
sles/hosts/<profile>/           per-machine user files + theme (layer 04)
sles/install.sh                 orchestrator: preflight, seed, phases, resume after reboot, verify, report, final reboot
sles/bootstrap.sh               fetch the code (no git) and start install.sh --unattended
sles/tools/sync-guest           copy the checkout to a guest without git
sles/tools/seed-repo            prebuilt RPMs + build stamps: the GitHub release (github) or another host
sles/tools/publish-repo         publish a host's built repo as a GitHub release (repo-<lock hash>)
sles/tools/greeter-check        is the machine at a greeter that will log the user in?
sles/tools/probe                what this host lacks (read-only); --reference dumps the package list
sles/layers/NN-name/            install.sh, verify.sh, AGENT.md, NOTES.md (+ layer-specific files)
/var/lib/omageeko/repo          local RPM repo (zypper alias omageeko-local), bind-mounted into transactions
```

The guest doesn't need git: `sles/tools/sync-guest <user@host>`.
