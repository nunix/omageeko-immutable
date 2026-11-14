# SLES layer 00 — notes

Written 2026-11-14 for the minimal-VM install (`sles16.1-min`, 192.168.122.79).

## Probe (minimal install vs the KDE VM)
- Minimal SLES 16.1 Immutable with Package Hub + `container_runtime_podman`: 832 packages; the KDE
  VM with everything installed: 1966. Already on the minimal install: PipeWire stack, Mesa/Vulkan,
  polkit, xdg-desktop-portal, gsettings/dconf/glib2-tools, fontconfig, flatpak, podman, distrobox,
  inotify-tools, python3, libappstream5, libgraphene. `graphical.target` is already the default.
- Every package of 00 and 01 is available in SLES + Package Hub/Backports (nothing MISSING).
- `--dry-run` of the whole system phase (00 + 01 + 01b + 02 + 03, seeded repo): 364 new packages,
  195 MiB download, ~645 MiB installed.

## Findings
- **Display manager: SDDM** (decision D-1 revised after the first run: greetd/tuigreet doesn't fit
  Omarchy). Upstream's setup: Wayland greeter in a minimal Hyprland (`start-hyprland -- --config
  /usr/share/sddm/hyprland.lua`), theme `omarchy` — shipped as `omageeko-sles-sddm` (vendored in
  `packages/omageeko-sles/sddm/`, installed by layer 03). On SLES `sddm-qt6` requires `xdm`
  (`display-manager-legacy.service`) and the Qt5 + Qt6 greeters; no Xorg is needed for the Wayland
  greeter. Layer 00 enables `sddm.service` directly (`Alias=display-manager.service`); the KDE install
  goes through `display-manager-legacy` + the `default-displaymanager` alternative (`target_dm`
  understands both). `/usr/bin/sddm` is `xdm_exec_t`. **Untested on SLES:** Hyprland as the greeter
  compositor under SELinux (`xdm_t`). Fallback if it fails: drop `/etc/sddm.conf.d/10-omarchy.conf`'s
  `DisplayServer=wayland` and add `xorg-x11-server` (X11 greeter, what the KDE install used).
- (First run, greetd: `greetd` requires the virtual `greetd-branding`; zypper picked
  `greetd-gtkgreet-xfce-wayland` with cage + wlroots unless `greetd-branding-upstream` was named.)
- rebootmgr default (`/usr/share/rebootmgr/rebootmgr.conf`): best-effort, 03:30 window. Overridden
  by `/etc/rebootmgr.conf` with `strategy=off`.
- Pulled in as dependencies anyway: `spice-vdagent` (by something in the GTK stack), `xkeyboard-config`.
- First run: `omarchy-provision-user` failed with 127 on `update-desktop-database`
  (`omarchy-refresh-applications`). Added `desktop-file-utils`, and `pkexec` (11 Omarchy scripts;
  also on the KDE VM). Checked the rest of the commonly called tools: only unused or marginal ones
  are absent (walker, swaybg, plocate, sensors).

## First minimal-VM run (2026-11-14): what broke, what changed
1. `install.sh` exited silently after the system phase: `rpm -qa --last | head` → SIGPIPE under
   `set -o pipefail`. Fixed (`{ …; } || true`).
2. Ghostty rebuilt on every layer 03 run: deploy stamp and build stamp were both `03-ghostty`.
   Deploy stamp renamed `03-ghostty-deployed`.
3. Resume unit `203/EXEC`: SELinux doesn't let systemd (`init_t`) exec a `user_home_t` script.
   `ExecStart=/usr/bin/bash <script>` (runs as `initrc_t`).
4. `omarchy-provision-user` → 127: `update-desktop-database` missing → `desktop-file-utils` (+ `pkexec`).
5. **Lock-out (VM lost):** after layer 04's first (partial) run, ssh keys were refused and the greeter
   login failed. Cause: `cp -a` out of `/tmp` staging dirs carries `*_tmp_t` labels, and layer 04's
   `cp -af "$SKEL/." "$HOME/"` applied the skel dir's label to `$HOME` itself. Proven on the KDE VM
   (`$HOME` is `user_tmp_t` there, which it survived); on the minimal VM the user phase ran from a
   system unit, so the stage label was a service tmp type that sshd/logins can't search (inferred:
   the VM had no root password and the guest agent is SELinux-confined, so no diagnosis was possible).
   Fixed: all copies use `--no-preserve=context`, layer 04 copies the skel's *entries*, the user phase
   ends with `sudo restorecon -R $HOME`, and layer 04's verify checks the labels.
   (`pam_faillock` is not in SLES's `common-auth`, so typed ssh passwords did not lock the account.)
6. Tools now use `ssh -o BatchMode=yes`: a broken key fails fast instead of prompting for passwords.

## Second minimal-VM run (2026-11-14, 192.168.122.226)
- **SDDM must run as `sddm.service`, not via `display-manager-legacy.service`.** Installing
  `sddm-qt6` pulls in `xdm`; its `%post` links `display-manager.service` to SUSE's legacy wrapper
  (`/usr/lib/X11/display-manager`, `default-displaymanager` alternative = sddm). That unit only
  `Conflicts=getty@tty7`; SDDM 0.21 takes VT1, so `getty@tty1` starts at the end of boot, hangs
  up VT1 and the greeter session dies with SIGHUP (`Greeter stopped. SDDM::Auth::HELPER_AUTH_ERROR`,
  black screen, no core dump, no AVC). `sddm.service` has `Conflicts=getty@tty1`. Diagnosed with a
  compositor wrapper (`CompositorCommand=/usr/bin/bash wrap.sh`) logging signals and exit codes.
- Restarting the display manager in place (`systemctl restart`) on this VM always ends in
  `HELPER_TTY_ERROR` loops; test greeter changes with a reboot.
- Hyprland as the greeter compositor (`xdm_t`) works under SELinux: no denials.
