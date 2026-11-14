# Agent guide: omageeko-immutable

omageeko (Omarchy's Hyprland desktop on openSUSE) on **SLES 16.1 Immutable**. Read `README.md`,
`sles/README.md` and `sles/PLAN-install.md` (§9 results, §10 current plan) before changing anything.

## Rules (do not relitigate)

- **The host changes only through `transactional-update`**, one pending snapshot per run, via the
  helpers in `sles/lib/common.sh` (`tu_run`, `host_install`, `install_from_repo`). Never run
  `zypper in` on a SLES host.
- **Userland first:** mise, Flatpak `--user`, distrobox (`omageeko-twbox`, Tumbleweed), podman.
  Packages Omarchy asks for at runtime go to the box or Flathub, never to the host.
- Omarchy lives in `~/.local/share/omarchy` (layer 03 option B) plus the `omageeko-sles` RPM.
  Upstream's sudoers rules are not shipped on purpose (root for scripts in a user-writable dir).
- Fixed decisions: D-1 SDDM upstream style (Wayland greeter in Hyprland, Omarchy theme, via
  `omageeko-sles-sddm`; greetd was rejected), D-2 keep foot, D-3 rebootmgr off, D-4 embed the
  tarball, D-5 host profile `kvm-guest` for VMs.
- Builds run in the SLES BCI builder (`sles/builder/`), SCC through podman secrets. Lock files pin
  everything (`01b-hyprland/hyprland.lock`, `02-build-rpms/build.lock`, `03-omarchy/build.lock`,
  `omageeko/upstream.lock`). The `omageeko/` submodule is the main repo: push omageeko first, then
  move the pin here.
- SELinux is enforcing. Anything written into `$HOME` from a system context must end up with
  default labels (`restorecon`); systemd can't exec `user_home_t` files (use `/usr/bin/bash <script>`).
- Each layer has `install.sh` (idempotent), `verify.sh`, `NOTES.md` (what was learned) and
  sometimes `AGENT.md` (how to rebuild it). Record surprises in the layer's `NOTES.md` and runs in
  PLAN §9.
- Deleting a test VM: `virsh undefine <vm> --nvram --tpm --storage vda`, never
  `--remove-all-storage` (it deletes the shared installer ISO).

## Installing omageeko on a SLES machine

Use the skill `.claude/skills/install-omageeko-immutable/SKILL.md`. Short form: the user runs
`sles/bootstrap.sh` on the machine (or you run `sles/tools/sync-guest` + `install.sh --unattended`
over ssh); you watch the install log and the resume unit, and map failures to the known-failure
table in the skill. The script holds the logic; never redo its steps by hand.
