# omageeko-immutable

[omageeko](https://github.com/nunix/omageeko) (Omarchy's Hyprland desktop, ported to openSUSE
Tumbleweed) on **immutable** SUSE systems. The host changes only through
`transactional-update` snapshots; everything else goes to userland (mise, Flatpak `--user`,
distrobox, podman).

Targets:

| Dir | Target | Status |
|---|---|---|
| [`sles/`](sles/) | SLES 16.1 Immutable (minimal install + Package Hub + podman) | verified in a KVM guest; bare metal next |

## Layout

```
sles/        the SLES target: install.sh orchestrator, layers 00-04, builder, tools, host profiles
packages/    specs only the immutable targets build (ghostty bundle, folio, omageeko-sles + SDDM greeter)
omageeko/    git submodule: the main omageeko repo (shared specs, upstream.lock, packages.map)
docs/        assessment and decisions; agent-onboarding.md
```

A spec in `packages/` wins over the submodule's `omageeko/packages/` of the same name.

## Get it

```bash
git clone --recurse-submodules https://github.com/nunix/omageeko-immutable.git
```

Installing on a machine needs no clone and no git: see
[`sles/README.md`](sles/README.md#install-from-scratch) (`sles/bootstrap.sh`). For development,
`sles/tools/sync-guest user@host` copies a checkout, submodule included. Agents: [`docs/agent-onboarding.md`](docs/agent-onboarding.md) (start here), then [`AGENTS.md`](AGENTS.md).
