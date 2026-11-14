#!/bin/bash
# SLES layer 02 - verify built RPMs
source "$(dirname "$(readlink -f "$0")")/../../lib/common.sh"
set +e
fail=0; ok() { printf '  \e[32mok\e[0m   %s\n' "$1"; }; bad() { printf '  \e[31mFAIL\e[0m %s\n' "$1"; fail=1; }
reboot_pending && bad "a newer snapshot is waiting for a reboot"
for p in quickshell owe owe-lockfeed omarchy-hyprland-titlebars hyprland-preview-share-picker ttfx folio; do
  v=$(rpm -q --qf '%{VERSION}-%{RELEASE} %{VENDOR}' "$p" 2>/dev/null)
  [[ $v == *omageeko* ]] && ok "$p ${v% *}" || bad "$p not installed from omageeko-local"
done
quickshell --version &>/dev/null && ok "quickshell --version" || bad "quickshell does not start"
quickshell --private-check-compat &>/dev/null && ok "quickshell Qt compat check" || bad "quickshell built against another Qt (OMAGEEKO_REBUILD=quickshell)"
[[ -f /usr/lib/omarchy-hyprland-titlebars/titlebars.so ]] && ok "titlebars plugin" || bad "titlebars plugin missing"
hypr=$(rpm -q --qf '%{VERSION}' hyprland); built=$(rpm -q --qf '%{RELEASE}' omarchy-hyprland-titlebars | sed -nE 's/.*\.h([0-9.]*[0-9]).*/\1/p')
[[ $built == "$hypr" ]] && ok "titlebars built for hyprland $hypr" || bad "titlebars built for '$built', hyprland is $hypr"
[[ -f /usr/lib64/qt6/qml/Owe/LockFeed/qmldir ]] && ok "Owe.LockFeed QML module" || bad "Owe.LockFeed QML module missing"
for c in owed owe hyprland-preview-share-picker ttfx folio; do command -v "$c" &>/dev/null && ok "command: $c" || bad "command missing: $c"; done
exit $fail
