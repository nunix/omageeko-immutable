# SLES layer 01 — notes

Status: **applied and verified 2026-11-13** (host packages in snapshot #5 → active #7).

- Host gets only `host.packages` (16 packages): terminal, Wayland helpers, jq/git/unzip,
  notify-send, gnome-keyring + secret-tool. Everything else of TW's layer 01 is userland or deferred.
- mise: release binary from GitHub verified against `SHASUMS256.txt` (no piped installer);
  15 base CLI tools from aqua/GitHub releases (prebuilt, nothing compiled).
- Fonts: `symbols-only-nerd-fonts`, `fontawesome-fonts` unpacked from SLES RPMs into
  `~/.local/share/fonts` inside the builder (`sles_payload`), never installed on the host.
- Browser: **Brave** (since 2026-11-15, the user's choice; Chromium before), Flathub `--user`
  (`com.brave.Browser`). `~/.local/bin/brave` + hidden `brave-browser.desktop` alias give
  Omarchy's names a target (web apps run the first word of the entry's Exec, which can't be
  `flatpak`). Layer 04 sets it as the default from the host profile file `browser` and creates
  `~/.config/brave-flags.conf` from Omarchy's chromium flags. The flags file and the userland tree
  (bundled extensions) reach the sandbox through `flatpak override --filesystem` only.
  Chromium works the same way when listed in `user-flatpaks`.

## Findings
- **Run 5: the browser never started.** `chromium-flags.conf` was symlinked into
  `~/.var/app/org.chromium.Chromium/config` *and* exposed with `--filesystem=xdg-config/...`.
  Flatpak 1.16 also mounts xdg-config paths into the per-app config dir, onto the symlink: bwrap
  failed ("Can't create file at …/chromium-flags.conf"), the launcher exited 1, so Super+Shift+B
  did nothing and `git`'s HTTPS device login couldn't open a page. The symlink is gone (removed on
  rerun); verify now starts each browser's sandbox (`flatpak run --command=true`).
- `cp -a --no-preserve=context` still copies the SELinux label (it's an xattr): fonts copied from
  a /tmp stage kept `user_tmp_t` when the layer ran alone. All stage copies use
  `--no-preserve=context,xattr` now (layers 01/03/04); `install.sh`'s final restorecon used to hide it.
- SLES's `gnome-themes-extras` is the GNOME 2 theme set (Darklooks, Unity, ...), not Arch's
  `gnome-themes-extra`. Not needed: GTK 3.24/4 have Adwaita-dark built in.
- SLES doesn't index file capabilities like `/usr/bin/secret-tool`: use package names.
- GitHub's anonymous API limit (60/h) is easily used up by mise; it shows as a flood of
  "no versions found" warnings for Omarchy's lazy agent tools and clears within the hour.

## Deferred (optional features, install when wanted)
ffmpeg (screen recording/transcode), qrencode/zbar/tesseract (QR/OCR), CJK fonts, udiskie,
fcitx5. Not in SLES: gpu-screen-recorder, yaru-icon-theme. With layer 03's overlay these
install through `omarchy pkg add` into the Tumbleweed box.

## 2026-11-13: autostart errors
- `udiskie` (Omarchy autostarts `udiskie --automount`) added to the host packages: it automounts
  through the host's udisks2 over the system bus, so it belongs on the host (SLES Backports 2.5.3).
- `herdr` (autostarted as `herdr server`) comes from mise (`aqua:herdrdev/herdr`, prebuilt) instead
  of an RPM build.

## 2026-11-14: terminal launch
- Super+Enter and the screensaver failed because SLES Backports' `xdg-terminal-exec` (20240120)
  predates `--dir`/`--print-id`: it passed them to foot, which rejected them. The host package is
  now removed (`host.remove`) and v0.14.4 lives in `~/.local/bin` (tag tarball, pinned SHA-256,
  version marker on line 2). The host copy had to go: `~/.local/bin` comes after `/usr/bin` on PATH.
- foot stays on the host as the fallback terminal; Ghostty (layer 03) is the default.
- `sles/overlay/share/pkgmap-sles.tsv` + `cmd:` targets: names the SLES layers provide (ghostty,
  xdg-terminal-exec, herdr, chromium) count as present when the command exists, so
  `omarchy-install-terminal ghostty` & co. don't install a second copy in the Tumbleweed box.

## 2026-11-14: phase split (install from scratch)
`--phase system` = `host.packages` + `host.remove` (snapshot); `--phase user` = xdg-terminal-exec,
mise, fonts, Flathub Chromium. The user part needs `flatpak` on the host: on a minimal install it
comes from layer 00, so it runs after the reboot (`sles/install.sh` orders it).
