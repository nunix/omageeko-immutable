# Agent onboarding: omageeko and omageeko-immutable

Read this when you (an AI coding agent) start on a machine of this project with no memory of
it, or when you need to get your bearings. It explains what the project is, where every piece of
information lives, and how to get the skills that make you useful here.

## What omageeko is

[Omarchy](https://omarchy.org/) (upstream `omacom/omarchy`, branch `quattro`) is an opinionated
Hyprland desktop for Arch Linux: the `omarchy` CLI, a Quickshell bar and menus, themes, keybinds,
web apps. **omageeko** is that desktop on SUSE instead of Arch, layer by layer, keeping upstream's
look and behaviour and changing only what the base OS forces.

| | omageeko | omageeko-immutable |
|---|---|---|
| Base | openSUSE Tumbleweed (mutable, rolling) | SLES 16.1 Immutable (transactional, read-only root) |
| Repo | github.com/nunix/omageeko | github.com/nunix/omageeko-immutable (omageeko as the `omageeko/` submodule) |
| Omarchy itself | RPMs in system paths (`/usr/share/omarchy`) | userland tree `~/.local/share/omarchy`, built from the same RPMs |
| Host changes | zypper, snapper pairs | `transactional-update` only, one snapshot per run, active after reboot |
| Apps | Tumbleweed repos, vendor repos, Flathub, Arch box | userland first: mise, Flathub `--user`, Tumbleweed box, Arch box, podman |
| Agent skill | `omageeko` | `sles-atomic` (wins), `omageeko` as background |

Both pin upstream in `omageeko/upstream.lock` (an Omarchy release, e.g. v4.5.0) and rebuild
Omarchy's packages locally. omageeko-immutable reuses omageeko's specs, package map and patches
through the submodule and adds the immutable layers.

## Which machine am I on?

```bash
. /etc/os-release; echo "$ID $VERSION_ID ${VARIANT_ID:-}"   # sles 16.1 transactional = immutable
cat /sys/class/dmi/id/product_name                         # 21K6S0A00C = the user's ThinkPad P14s Gen 4
ls ~/.local/share/omarchy 2>/dev/null && echo "userland Omarchy (immutable)"
```

## Skills: get them locally

On an installed **omageeko-immutable** system, layer 04 already links them; check with
`ls -l ~/.claude/skills`:

| Skill | Source on the machine | For |
|---|---|---|
| `sles-atomic` | `~/.local/share/omageeko/agents/skills/sles-atomic` | this system: where apps go, updates, immutable facts, hardware, the checkout |
| `omageeko` | `~/.local/share/omageeko/agents/skills/omageeko` (paths adapted to userland) | the Tumbleweed sibling; background |
| `omarchy`, `omarchy-app`, `diagnose-crash` | `~/.local/share/omarchy/default/agents/skills/*` | upstream Omarchy: desktop customization, apps, crashes |
| `install-omageeko-immutable` | `~/omageeko-immutable/.claude/skills/` (project skill) | installing / repairing an install, known failures |

Missing links (e.g. on a system installed before 2026-11-15): rerun layers 03 and 04, which deploy
and link them idempotently:

```bash
~/omageeko-immutable/sles/layers/03-omarchy/install.sh --phase user
~/omageeko-immutable/sles/layers/04-session/install.sh
```

Without an install (another machine, reading only): link straight from a checkout:

```bash
git clone --recurse-submodules https://github.com/nunix/omageeko-immutable.git ~/omageeko-immutable
mkdir -p ~/.claude/skills
ln -sfn ~/omageeko-immutable/sles/overlay/share/agents/skills/sles-atomic ~/.claude/skills/sles-atomic
ln -sfn ~/omageeko-immutable/omageeko/packages/omageeko/overlay/share/agents/skills/omageeko ~/.claude/skills/omageeko
```

(The checkout copy of `omageeko` still has Tumbleweed's system paths; the deployed one is adapted.)

## Where the information lives

Read in this order; each one links further:

1. `AGENTS.md` (= `CLAUDE.md`) in omageeko-immutable: the rules and fixed decisions.
2. `README.md`, then `sles/README.md`: layout, layers, how an install runs.
3. `sles/PLAN-install.md`: the plan, decisions D-1…D-5, and **§9 results of every run** (runs 1-8),
   i.e. every bug found and why the code looks the way it does. §10: the plan behind bootstrap,
   the published repo and the greeter fixes.
4. `sles/layers/NN-*/NOTES.md` (findings per layer) and `AGENT.md` (how to rebuild a layer).
5. `.claude/skills/install-omageeko-immutable/SKILL.md`: install runbook, monitor loop, known failures.
6. `sles/hosts/<profile>/README.md`: per-machine setup (screens, keybinds, hardware packages).
7. In the omageeko submodule (Tumbleweed): `README.md`, `docs/`, `packages/omageeko/overlay/INDEX.md`
   (every change made to upstream Omarchy, and why), `docs/bump-runbook.md` (upstream bumps).
8. GitHub releases of omageeko-immutable named `repo-<hash>`: prebuilt RPMs that fresh installs seed from.

The user's own notes for you (memory) are not in the repos: Claude Code keeps them in
`~/.claude/projects/<cwd>/memory/`. If they were carried over from another machine, read `MEMORY.md` there first.

## Working rules (short form; AGENTS.md has the full list)

- Host: only through the layers / `transactional-update`. Never `zypper in` on SLES Immutable.
- Apps: userland first (`omarchy pkg add` does it right).
- Durable changes go into the checkout (layers, overlay patches, host profiles), then the layer reruns.
- Verify: `~/omageeko-immutable/sles/install.sh --phase verify`.
- The bootstrap checkout is a tarball without `.git`: clone the repo before committing.
- Ask the user before anything destructive or outward-facing (pushes, releases, reboots).
