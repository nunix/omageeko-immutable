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
docs/        assessment and decisions
```

A spec in `packages/` wins over the submodule's `omageeko/packages/` of the same name.

## Get it

```bash
git clone --recurse-submodules https://github.com/nunix/omageeko-immutable.git
```

The SLES guest needs no git: `sles/tools/sync-guest user@host` copies the checkout, submodule
included. Then follow [`sles/README.md`](sles/README.md#install-from-scratch).
