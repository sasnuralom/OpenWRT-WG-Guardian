#!/bin/sh
# OpenWrt WG Guardian - clean installer
# POSIX/BusyBox ash compatible. Does not modify /etc/config/firewall.

set -u
APP=wg-guardian
BASE=/etc/wg-guardian
CONFIG=$BASE/config
RUNTIME=/usr/sbin/wg-guardian
INIT=/etc/init.d/wg-guardian
RECOVERY=/root/wg-guardian-backups
TAG=wg-guardian

say(){ printf '%s\n' "$*"; }
fail(){ say "ERROR: $*" >&2; exit 1; }
ask(){ # prompt default; result in REPLY
  prompt=$1 default=$2
  while :; do
    printf '%s [%s]: ' "$prompt" "$default" >&2
    IFS= read -r REPLY || exit 1
    [ -n "$REPLY" ] || REPLY=$default
    case "$REPLY" in *[!A-Za-z0-9_.:-]*|'') say 'Use letters, numbers, underscore, dot, colon or hyphen.' >&2;; *) return 0;; esac
  done
}

[ "$(id -u)" = 0 ] || fail 'Run as root.'
command -v uci >/dev/null 2>&1 || fail 'uci is required (run this on OpenWrt).'
command -v ubus >/dev/null 2>&1 || fail 'ubus is required.'
command -v wg >/dev/null 2>&1 || fail 'wireguard-tools (wg) is required.'

say '================================================='
say ' OpenWrt WG Guardian - Fresh Installer'
say ' Existing firewall configuration will NOT be changed.'
say '================================================='

# Detect WG interface
WG_IF=
for s in $(uci show network 2>/dev/null | sed -n "s/^network\.\([^.=]*\)\.proto='wireguard'.*/\1/p"); do WG_IF=$s; break; done
[ -n "$WG_IF" ] || fail 'No UCI WireGuard interface found.'
WAN_LOGICAL=wan
WAN_DEV=$(ubus call network.interface.$WAN_LOGICAL status 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)
[ -n "$WAN_DEV" ] || WAN_DEV=$(ip -4 route show default 2>/dev/null | awk 'NR==1{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1);exit}}')
[ -n "$WAN_DEV" ] || fail 'Could not detect WAN device. Ensure network.interface.wan is up.'

say "Detected WireGuard UCI interface: $WG_IF"
say "Detected WAN device: $WAN_DEV"

# The interface must not race the clock at boot. Guardian owns its startup.

# Validate existing full-tunnel peer configuration; never silently rewrite it.
if ! uci show network | grep -q "network\.$WG_IF\.\(@wireguard_.*\|[0-9]*\)\.route_allowed_ips='1'"; then
  say 'WARNING: Could not confirm route_allowed_ips=1 on a WireGuard peer.'
  say 'For all-LAN full-tunnel routing, at least one peer normally needs AllowedIPs 0.0.0.0/0 and route_allowed_ips 1.'
  printf 'Continue anyway? [y/N]: ' >&2
  IFS= read -r yn
  case "$yn" in y|Y|yes|YES) ;; *) exit 1;; esac
fi

say ''
say 'Failure policy: Automatic WAN fallback (only mode in this release).'
say 'Guardian will bring the WG interface down on detected failure so the normal WAN default route can take over.'
say 'It will retry the interface in the background and return to VPN after recovery.'
say ''
printf 'Install fresh Guardian components? [y/N]: ' >&2
IFS= read -r yn
case "$yn" in y|Y|yes|YES) ;; *) say 'Cancelled; no changes made.'; exit 0;; esac

# Independent, mandatory backup before cleanup or config mutation.
mkdir -p "$RECOVERY" || fail 'Cannot create recovery directory.'
chmod 700 "$RECOVERY"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP=$RECOVERY/pre-install-$STAMP.tar.gz
 tar -czf "$BACKUP" /etc/config/network /etc/config/firewall /etc/config/dhcp /etc/config/system /etc/sysctl.conf "$BASE" /usr/sbin/wg-guardian /etc/init.d/wg-guardian 2>/dev/null || {
  rm -f "$BACKUP"; fail 'Pre-install backup failed. No cleanup performed.';
}
chmod 600 "$BACKUP"
say "Backup created: $BACKUP"

# Stop and remove only Guardian-owned files/service. Firewall is deliberately untouched.
if [ -x "$INIT" ]; then "$INIT" stop >/dev/null 2>&1 || true; "$INIT" disable >/dev/null 2>&1 || true; fi
[ -f /etc/rc.d/S99wg-guardian ] && rm -f /etc/rc.d/S99wg-guardian
rm -f "$INIT" "$RUNTIME"
rm -rf "$BASE"
mkdir -p "$BASE" || fail 'Cannot create Guardian directory.'
chmod 700 "$BASE"

cat > "$CONFIG" <<EOF_CFG
WG_IF='$WG_IF'
WAN_LOGICAL='$WAN_LOGICAL'
WAN_DEV='$WAN_DEV'
CHECK_INTERVAL=30
RETRY_INITIAL=15
RETRY_MAX=300
HANDSHAKE_STALE=180
NTP_WAIT_INTERVAL=10
NTP_VALID_EPOCH=1704067200
EOF_CFG
chmod 600 "$CONFIG"

# Disable automatic WG startup so it cannot start before time synchronization.
uci set network."$WG_IF".auto='0' || fail 'Could not disable automatic WireGuard startup.'
uci commit network || fail 'Could not commit WireGuard boot setting.'
say 'WireGuard automatic boot startup disabled; Guardian will start it after NTP sync.'

cat > "$RUNTIME" <<'EOF_RUN'
#!/bin/sh
set -u
CONFIG=/etc/wg-guardian/config
[ -r "$CONFIG" ] || exit 1
. "$CONFIG"
TAG=wg-guardian
log(){ logger -t "$TAG" "$*"; }
wan_up(){ ubus call "network.interface.$WAN_LOGICAL" status 2>/dev/null | grep -q '"up": true'; }
clock_valid(){ now=$(date +%s 2>/dev/null); case "$now" in ''|*[!0-9]*) return 1;; esac; [ "$now" -ge "$NTP_VALID_EPOCH" ]; }
ntp_synced(){
  # OpenWrt sysntpd/BusyBox ntpd reports a successful sync in the system log.
  # Reboot clears the in-memory log, so this cannot be satisfied by a prior boot.
  clock_valid || return 1
  logread 2>/dev/null | grep -Eiq 'ntpd.*(synchronized|sync(ed)? to)'
}
wait_for_ntp(){
  log 'Waiting for successful NTP synchronization before starting WireGuard.'
  while :; do
    if ntp_synced; then log "NTP synchronized; system time is $(date)."; return 0; fi
    log 'NTP not synchronized yet; WireGuard remains down and WAN fallback remains available.'
    sleep "$NTP_WAIT_INTERVAL"
  done
}
endpoint_host(){
  # Obtain current endpoint from wg runtime. Output is host only; IPv6 literals are skipped.
  ep=$(wg show "$WG_IF" endpoints 2>/dev/null | awk 'NR==1{print $2}')
  [ -n "$ep" ] || return 1
  case "$ep" in *:*) host=${ep%:*};; *) host=$ep;; esac
  case "$host" in *[!A-Za-z0-9.-]*|'') return 1;; esac
  printf '%s\n' "$host"
}
endpoint_resolves(){
  h=$(endpoint_host) || return 1
  case "$h" in *[!0-9.]* ) nslookup "$h" 2>/dev/null | grep -q 'Address' ;; *) return 0;; esac
}
latest_handshake(){ wg show "$WG_IF" latest-handshakes 2>/dev/null | awk 'BEGIN{m=0}{if($2>m)m=$2}END{print m+0}'; }
handshake_fresh(){
  now=$(date +%s 2>/dev/null); hs=$(latest_handshake)
  [ "$hs" -gt 0 ] && [ $((now-hs)) -le "$HANDSHAKE_STALE" ]
}
wg_up(){ ubus call "network.interface.$WG_IF" status 2>/dev/null | grep -q '"up": true'; }
set_wg_down(){
  if wg_up; then
    log 'VPN unavailable; taking WireGuard interface down to allow WAN default route.'
    ifdown "$WG_IF" >/dev/null 2>&1 || ubus call "network.interface.$WG_IF" down >/dev/null 2>&1
  fi
}
try_wg(){
  log 'Attempting WireGuard recovery.'
  ifup "$WG_IF" >/dev/null 2>&1 || ubus call "network.interface.$WG_IF" up >/dev/null 2>&1 || return 1
  # Wait for handshake. No firewall config is edited.
  waited=0
  while [ "$waited" -lt 45 ]; do
    sleep 3; waited=$((waited+3))
    handshake_fresh && { log 'Fresh WireGuard handshake confirmed; VPN route restored.'; return 0; }
  done
  return 1
}
run_loop(){
  delay=$RETRY_INITIAL
  log "Guardian started: WG=$WG_IF WAN=$WAN_LOGICAL"
  # Defensively keep WG down until this boot has an NTP synchronization.
  if wg_up; then ifdown "$WG_IF" >/dev/null 2>&1 || true; fi
  while :; do
    if ! wan_up; then log 'WAN is down; waiting for WAN.'; sleep "$CHECK_INTERVAL"; continue; fi
    if ! ntp_synced; then
      wait_for_ntp
      delay=$RETRY_INITIAL
    fi
    if wg_up && handshake_fresh; then delay=$RETRY_INITIAL; sleep "$CHECK_INTERVAL"; continue; fi
    if wg_up; then log 'WireGuard has no recent handshake; checking endpoint.'; fi
    if ! endpoint_resolves; then
      log 'WireGuard endpoint DNS resolution failed; enabling WAN fallback.'
      set_wg_down
    else
      if try_wg; then delay=$RETRY_INITIAL; sleep "$CHECK_INTERVAL"; continue; fi
      log "WireGuard recovery attempt failed; WAN fallback remains active. Next retry in ${delay}s."
      set_wg_down
    fi
    sleep "$delay"
    [ "$delay" -ge "$RETRY_MAX" ] || delay=$((delay*2))
    [ "$delay" -le "$RETRY_MAX" ] || delay=$RETRY_MAX
  done
}
status(){
  echo "WireGuard interface: $WG_IF"
  echo "WAN logical interface: $WAN_LOGICAL"
  echo "WAN device at install: $WAN_DEV"
  echo "WAN up: $(wan_up && echo yes || echo no)"
  echo "WG up: $(wg_up && echo yes || echo no)"
  echo "Fresh handshake: $(handshake_fresh && echo yes || echo no)"
  wg show "$WG_IF" 2>/dev/null
}
case "${1:-daemon}" in daemon) run_loop;; status) status;; *) echo "Usage: $0 {daemon|status}"; exit 2;; esac
EOF_RUN
chmod 755 "$RUNTIME"

cat > "$INIT" <<'EOF_INIT'
#!/bin/sh /etc/rc.common
# Start after network and sysntpd have been launched; daemon still waits for confirmed sync.
START=99
STOP=10
USE_PROCD=1

start_service() {
  procd_open_instance
  procd_set_param command /usr/sbin/wg-guardian daemon
  procd_set_param respawn 3600 5 5
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_close_instance
}
EOF_INIT
chmod 755 "$INIT"

# Ensure endpoint has a WAN route via the WAN default route. Do not alter firewall.
/etc/init.d/network reload >/dev/null 2>&1 || true
"$INIT" enable || fail 'Could not enable Guardian service.'
"$INIT" start || fail 'Could not start Guardian service.'

say ''
say 'WG Guardian installed.'
say 'Firewall configuration was not modified.'
say 'WireGuard auto-start is disabled; Guardian waits for NTP synchronization on every boot before starting it.'
say "Backup: $BACKUP"
say 'Commands:'
say '  /usr/sbin/wg-guardian status'
say '  /etc/init.d/wg-guardian restart'
say '  logread -f -e wg-guardian'
say ''
say 'Boot sequence: WAN up -> confirmed NTP sync -> WireGuard start -> fresh handshake.'
say 'If NTP is unavailable, WireGuard stays down and Guardian keeps waiting while WAN remains available.'
say 'IMPORTANT: This service relies on your existing OpenWrt VPN firewall zone and LAN forwarding.'
say 'It does not create or modify firewall zones, LAN forwarding, AllowedIPs, or default routes.'
say 'Verify full-tunnel routing and WAN fallback before relying on it.'
