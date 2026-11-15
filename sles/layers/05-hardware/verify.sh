#!/bin/bash
# SLES layer 05 - verify the hardware layer
source "$(dirname "$(readlink -f "$0")")/../../lib/common.sh"
set +e
fail=0; ok() { printf '  \e[32mok\e[0m   %s\n' "$1"; }; bad() { printf '  \e[31mFAIL\e[0m %s\n' "$1"; fail=1; }
PROFILE="${OMAGEEKO_HOST_PROFILE:-kvm-guest}"
HOST_PACKAGES="$OMAGEEKO_SLES/hosts/$PROFILE/host.packages"
if systemd-detect-virt -q && [[ ! -f $HOST_PACKAGES ]]; then
  ok "virtual machine with profile $PROFILE: no hardware layer"
  exit 0
fi
reboot_pending && bad "a newer snapshot is waiting for a reboot"
if [[ -f $HOST_PACKAGES ]]; then
  while read -r p; do
    rpm -q --whatprovides "$p" &>/dev/null && ok "host package $p" || bad "host package $p missing"
  done < <(grep -vE '^[[:space:]]*(#|$)' "$HOST_PACKAGES")
fi
for p in omageeko-hardware bluez-tools; do
  v=$(rpm -q --qf '%{VERSION}' "$p" 2>/dev/null) && ok "$p $v" || bad "$p not installed"
done
[[ -x /usr/bin/bt-agent ]] && ok "bt-agent (Bluetooth pairing agent)" || bad "/usr/bin/bt-agent missing: pairing would loop"
for u in power-profiles-daemon.service omageeko-bt-device-privacy.service omageeko-bt-device-privacy.timer bluetooth.service; do
  systemctl is-enabled -q "$u" 2>/dev/null && ok "$u enabled" || bad "$u not enabled"
done
systemctl --user is-enabled -q bt-agent.service 2>/dev/null && ok "bt-agent.service (user) enabled" || bad "bt-agent.service (user) not enabled"
if [[ -f $HOME/.config/omageeko/monitor-wake-kick ]]; then
  systemctl --user is-enabled -q omageeko-monitor-wake-kick.service && ok "monitor wake kick enabled" || bad "monitor wake kick not enabled"
  exe=$(systemctl --user show -P ExecStart omageeko-monitor-wake-kick.service | sed -n 's/.*path=\([^ ;]*\).*/\1/p')
  [[ -x $exe ]] && ok "monitor wake kick runs $exe" || bad "monitor wake kick ExecStart '${exe:-?}' missing (203/EXEC loop)"
fi
exit $fail
