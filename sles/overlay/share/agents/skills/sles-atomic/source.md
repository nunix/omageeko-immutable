# The source: ~/omageeko-immutable

## Layout

```
sles/install.sh        orchestrator: preflight, seed, system phase (one snapshot), reboot,
                       user phase (resume unit, greeter held), verify, report, final reboot
sles/bootstrap.sh      fetch the code without git and start install.sh --unattended
sles/layers/NN-*/      install.sh (idempotent, --phase system|user), verify.sh, NOTES.md, AGENT.md
                       00 bootstrap · 01 base · 01b Hyprland · 02 built RPMs · 03 Omarchy · 04 session · 05 hardware
sles/hosts/<profile>/  per-machine files (see hardware.md)
sles/overlay/          SLES replacements (bin/), data (share/), patches/ (tree-*, config-*, fuzz 0)
sles/tools/            probe, sync-guest, seed-repo, publish-repo, greeter-check
sles/PLAN-install.md   plan, decisions, results of every run (§9)
packages/              specs only the immutable target builds (ghostty, folio, omageeko-sles)
omageeko/              submodule: the main omageeko repo (shared specs, upstream.lock, packages.map)
.claude/skills/install-omageeko-immutable/   install runbook + known failures
```

A checkout from `bootstrap.sh` is a tarball (no `.git`): clone the repo to commit.

## Making a change durable

| Change | Where |
|---|---|
| Host package for every machine | the layer's `host.packages` (00/01) or a lock entry (01b/02/03) |
| Host package for one machine | `sles/hosts/<profile>/host.packages` (layer 05) |
| Fix an Omarchy command | `sles/overlay/patches/tree-NN-*.patch` (diff against the RPM's file, fuzz 0) or a replacement in `sles/overlay/bin/` |
| Per-user default | layer 04 or the host profile |
| A new built package | spec in `packages/` (or the submodule), entry at the **end** of a lock (earlier entries cascade rebuilds) |

After changing what layers 01b/02/03 build: rebuild on a machine, then
`sles/tools/publish-repo user@host` publishes the RPMs as a GitHub release (`repo-<lock hash>`),
which fresh installs seed from (`--seed github`, default).

## Running and recovering

- `sles/install.sh` reruns are safe: no build, no snapshot, no reboot when nothing changed.
- A failed step clears the step marks: fix, rerun, it repeats that phase.
- Verify: `sles/install.sh --phase verify`. Logs: `~/.local/state/omageeko/install-*.log`.
- Known failures: `.claude/skills/install-omageeko-immutable/SKILL.md`.
