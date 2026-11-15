---
name: install-omageeko-immutable
description: Install, watch and repair an omageeko install on a SLES 16.1 Immutable machine (VM or bare metal) with sles/bootstrap.sh / sles/install.sh. Use when asked to install omageeko on SLES, run or monitor a fresh-VM / bare-metal pass, follow PLAN-install.md, or debug a failed install (greeter, resume unit, verify failures, SELinux, seeding).
---

# Install omageeko on SLES 16.1 Immutable

The scripts do the work. Your job is to set up access, start them, watch them, explain what
happens, and when something fails, find the cause with the table below. Don't redo script steps
by hand, and don't run `zypper in` on the host. Read `AGENTS.md` for the rules.

## Inputs

- Target: `user@ip` (ssh) or "local". Ask for the IP when the user hasn't given it.
- Host profile: `kvm-guest` for libvirt VMs; real hardware needs its own `sles/hosts/<profile>/`
  (copy `kvm-guest`, adjust `home/.config/hypr/*.lua`, `omarchy/shell.json`, `theme`, `terminal`).
- Seed: `github` (default), `none` (full local build, ~50 min), or `user@host`.

## Prerequisites (the user does these in the installer)

Minimal SLES 16.1 **Immutable**, registered with SCC, **Package Hub** add-on, pattern **Container
Runtime (podman)**, user in `wheel`, **root password set**, sshd enabled. Passwordless sudo is
set up by `bootstrap.sh` (asks once) if missing.

## Runbook

1. **Access** (remote targets): `ssh-keygen -R <ip>`; `ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new user@ip true`.
   No key yet: ask the user to run `! ssh-copy-id user@ip`. Check `sudo -n true`, `rpm -qa | wc -l`
   (~838 on a fresh minimal install), `sudo passwd -S root` (P = password set).
2. **Probe** (read-only, optional): after a fetch, `~/omageeko-immutable/sles/tools/probe`; everything
   must be `installed` or `available`, and SLES + PackageHub `Registered`.
3. **Start**, one of:
   - the user, on the machine: `curl -fsSLo /tmp/omageeko-bootstrap.sh https://raw.githubusercontent.com/nunix/omageeko-immutable/main/sles/bootstrap.sh && bash /tmp/omageeko-bootstrap.sh`
   - you, over ssh, released code: `ssh user@ip 'curl -fsSLo /tmp/b.sh https://raw.githubusercontent.com/nunix/omageeko-immutable/main/sles/bootstrap.sh && setsid nohup bash /tmp/b.sh >/tmp/bootstrap.out 2>&1 </dev/null &'`
   - you, development checkout: `sles/tools/sync-guest user@ip`, then
     `ssh user@ip 'setsid nohup ~/omageeko-immutable/sles/install.sh --unattended >/tmp/omageeko-install.out 2>&1 </dev/null &'`
4. **Watch** with a Monitor (one event per step, error, reboot and the end). Logs:
   `~/.local/state/omageeko/install-*.log` (one per invocation; they survive the reboots),
   resume unit `omageeko-sles-resume.service` (`ActiveState` is `activating` while it runs),
   report `~/.local/state/omageeko/install-report.txt`, greeter result
   `/var/lib/omageeko/greeter-check.txt` (after the final reboot). Example poll loop (prints new
   step lines, notices reboots, ends on the greeter result):
   ```bash
   H=user@ip; seen=0; down=0
   while true; do
     out=$(ssh -o BatchMode=yes -o ConnectTimeout=4 $H 'cat ~/.local/state/omageeko/install-*.log 2>/dev/null | sed "s/\x1b\[[0-9;]*m//g" | grep -nE "\[omageeko-sles\]|FAIL|Error:|failed"; echo "@@END $(tail -n1 /var/lib/omageeko/greeter-check.txt 2>/dev/null)"' 2>/dev/null)
     if [ -z "$out" ]; then [ $down = 0 ] && echo "unreachable (reboot?)"; down=1; sleep 10; continue; fi
     [ $down = 1 ] && echo "back"; down=0
     lines=$(grep -v '^@@END' <<<"$out"); n=$(wc -l <<<"$lines")
     [ "$n" -gt "$seen" ] && { tail -n +$((seen+1)) <<<"$lines" | cut -c1-200; seen=$n; }
     grep -q '^@@END greeter:' <<<"$out" && { grep '^@@END' <<<"$out"; exit 0; }
     grep -q 'verify FAILED\|failed (log:' <<<"$lines" && { echo "STOPPED ON FAILURE"; exit 1; }
     sleep 20
   done
   ```
   Expected flow (seeded, VM, run 4): preflight → seed ~10 s (0.9 GiB) → 00 ~50 s → 01 system ~15 s →
   01b ~45 s (builder image, no package builds) → 02 ~25 s → 03 system ~5 s → reboot → (no greeter:
   text console with progress) 01 user ~45 s → 03 user ~15 s → 04 ~10 s → verify all → report →
   final reboot → `greeter: ready (...)`. About 5 minutes in total.
   Any `Building <pkg>` line in a seeded run means a stamp mismatch: note which package and why.
5. **Accept**: every verify OK, `greeter: ready`, then the user's checklist (PLAN R9): first
   login works without anything else, theme intro plays, bar/notifications, Super+Enter Ghostty,
   Super+Shift+F Files, Super+Space menu, screensaver, lock/unlock, audio OSD, Super+Shift+Enter
   Chromium, `omarchy pkg add qrencode` → Tumbleweed box, logout. Footprint: `rpm -qa | wc -l`
   (~1232), `snapper list`.
6. **Record** the run in `sles/PLAN-install.md` §9 (setup, timings from the report, footprint,
   surprises and fixes) and the memory file, then commit when the user asks.

## Known failures

| Symptom | Cause | Fix / where |
|---|---|---|
| Greeter login: "user unknown", `Authentication for user "" failed` | greeter started before layer 04 wrote `/var/lib/sddm/state.conf` (run 3) | 04 restarts sddm when `greeter_stale`; by hand: `sudo systemctl restart sddm` (only when nobody is logged in) |
| Black screen / greeter killed at end of boot, `HELPER_AUTH_ERROR`, SIGHUP | `display-manager.service` → xdm's `display-manager-legacy.service`; `getty@tty1` takes VT1 (run 2) | layer 00 links `sddm.service`; 00 verify FAILs on the legacy unit |
| ssh key refused, login fails after layer 04 | `$HOME` relabelled with a /tmp label (run 1) | `sudo restorecon -R ~` from the root console; 04 verify checks labels |
| Resume unit `203/EXEC` | systemd can't exec `user_home_t` | unit runs `/usr/bin/bash install.sh` (fixed) |
| Silent exit after the system phase | SIGPIPE + pipefail (`… \| head`) | wrap in `{ …; } \|\| true` |
| Seeded run rebuilds Ghostty or other packages | `build_lock` cascade: an earlier entry changed | order locks so rarely-changing entries come first; check `.stamps` vs `entry_stamp` |
| `transactional-update command failed`, no snapshot kept | the command inside the transaction failed | `/var/log/transactional-update.log` |
| Preflight: Package Hub not registered | add-on skipped in the installer | `sudo SUSEConnect -p PackageHub/16.1/x86_64` (install.sh does it with `--yes`) |
| Builder: no SCC repos in the container | registration missing / secrets stale | `SUSEConnect -s`; `refresh_scc_secrets` reruns on every layer |
| Verify failed at the end | see the FAIL lines | fix, then rerun `sles/install.sh`: step marks were cleared, layers are idempotent |
| No greeter-check file after the final reboot | unit didn't run | `journalctl -b -u omageeko-sles-greeter-check`; run `sles/tools/greeter-check` by hand |
| Text console, no greeter, after the first reboot | expected: greeter held (`/var/lib/omageeko/greeter-hold`) while the user phase runs | wait; the hold is removed when the resume unit stops (even on failure); `sudo systemctl start display-manager` |
| `install.state: Permission denied` right after preflight | `/var/lib/omageeko` root-owned (run 4, fixed in `9c8fb98`) | update the checkout |

Recovery when the user account is broken: the root password at the VM console (virt-viewer). The
SLES guest agent has `guest-exec` disabled and is SELinux-confined, so don't rely on it.
