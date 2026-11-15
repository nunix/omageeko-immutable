# Apps: where software goes (userland first)

The host root is read-only and changes only with a reboot, so software goes to the first place
in this list that fits. `omarchy pkg add <arch-name>` (and the Install menus) already follow it:
it reads Omarchy's Arch names, translates them through `~/.local/share/omageeko/pkgmap.tsv` and
the SLES overrides `pkgmap-sles.tsv`, and installs into userland only.

| # | Where | For | How |
|---|---|---|---|
| 1 | **Already on the host** (the layers) | the desktop stack, drivers, daemons | nothing: `rpm -q <pkg>`; `pkgmap-sles.tsv` marks what the layers provide (`@cmd:`) |
| 2 | **mise** | CLI tools, language runtimes, agent CLIs (claude, codex, gh…) | `mise use -g <tool>`; Omarchy's own list is `~/.config/mise/conf.d/omarchy-tools.toml` (lazy installs) |
| 3 | **Flathub `--user`** | GUI apps | `flatpak install --user flathub <app-id>`; browsers also need Omarchy's command + desktop id (see below) |
| 4 | **Tumbleweed box** (`omageeko-tw`) | anything packaged for openSUSE, incl. vendor repos (Chrome, VS Code, 1Password…) | `omageeko-twbox install <tw-name>`; exports launchers and commands the host lacks |
| 5 | **Arch box** | Omarchy's Arch-only builds | `omageeko-box install <pkg>` |
| 6 | **podman** (rootless) | services, databases, dev stacks | `podman run …`, quadlets in `~/.config/containers/systemd/` |
| 7 | **The host** | only what needs the kernel, PAM, udev, systemd system units, or the greeter | a layer in the checkout (`sles/layers/*/host.packages`, or the profile's `host.packages` for one machine), then the layer's `install.sh` → one snapshot → reboot |

## Rules of thumb

- Same tool in two places shadows itself in `PATH`: check `command -v` / `type -a` first.
- A Flathub browser needs what layer 01 sets up for Brave: a `~/.local/bin/<cmd>` shim (Omarchy runs
  the first word of the desktop entry's Exec), a hidden alias under Omarchy's desktop id, and the
  flags file exposed with `flatpak override --filesystem=xdg-config/<flags>:ro` (never a symlink
  into `~/.var/app`: bwrap fails). Default browser: the host profile's `browser` file (layer 04).
- Remove what `omarchy pkg add` installed with `omarchy pkg drop` (it never touches the host).
- Need a host package durably? Add it to the right layer's list in the checkout, run that layer,
  tell the user a reboot activates it. Don't run `transactional-update pkg install` ad hoc.
