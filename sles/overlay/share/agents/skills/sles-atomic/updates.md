# Updates, snapshots, rollback

## omageeko-update (what `omarchy update` runs)

| Part | Does | Reboot? |
|---|---|---|
| host | `transactional-update up`: SLES updates into a new snapshot | yes, to activate |
| omageeko | the SLES layers from `~/omageeko-immutable`: Hyprland stack (01b), built RPMs (02), userland Omarchy tree (03), hardware (05) | only if a host package changed |
| apps | mise tools, per-user Flathub apps, Tumbleweed and Arch boxes | no |

`omageeko-update --check` lists what's pending and changes nothing. Bumping Omarchy itself:
`omageeko/` submodule pin (`upstream.lock`) moves in the main repo first, then here; layers 01b
and 03 rebuild what changed; publish the new binaries with `sles/tools/publish-repo` (see source.md).

## transactional-update facts

- Every host change is a transaction on top of the **booted** snapshot; a second one before the
  reboot must `--continue` the pending snapshot, or it drops the first one's changes. The layers'
  `tu_run` does that; ad-hoc commands must too.
- `/etc` changes made inside a transaction are merged into the running system; `/var` and `/home`
  aren't in root snapshots at all (Flatpak, containers, the local repo live in `/var`).
- transactional-update's exit status is unreliable; the layers check a marker the transaction writes.
- Logs: `/var/log/transactional-update.log`.

## Snapshots and rollback

```bash
snapper list                        # '*' = booted, '+' = default (next boot); different = reboot pending
sudo transactional-update rollback  # make the booted snapshot the default (after booting an older one)
sudo transactional-update rollback <n>   # set snapshot n as the next boot's root
```
- To undo a bad update: reboot, pick the previous snapshot in the boot menu, check it works, then
  `sudo transactional-update rollback`, reboot.
- rebootmgr is off (layer 00): reboots happen when the user decides.

## Is a reboot needed?

The default snapshot differs from the booted one (`snapper list`), or `zypper needs-rebooting`
returns 102 after a host update. Tell the user; don't reboot unasked.
