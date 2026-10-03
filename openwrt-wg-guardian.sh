#!/bin/sh
#
# ============================================================
# WireGuard Guardian - Interactive Installer
# OpenWrt 25.12.x
# ============================================================
#
# Usage:
#   chmod +x openwrt-wg-guardian.sh
#   ./openwrt-wg-guardian.sh
#
# The installer is POSIX / BusyBox sh compatible.
# ============================================================

APP="wg-guardian"
BASE="/etc/wg-guardian"
CONFIG="$BASE/config"
STATE="$BASE/state"
BACKUP_DIR="$BASE/backups"
RUNTIME="/usr/sbin/wg-guardian"
INIT="/etc/init.d/wg-guardian"
LOGTAG="wg-guardian"

RED="$(printf '\033[31m')"
GREEN="$(printf '\033[32m')"
YELLOW="$(printf '\033[33m')"
CYAN="$(printf '\033[36m')"
RESET="$(printf '\033[0m')"

msg() { printf '%s\n' "$*"; }
ok() { printf '%s[OK]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$*"; }
err() { printf '%s[ERROR]%s %s\n' "$RED" "$RESET" "$*"; }
info() { printf '%s[INFO]%s %s\n' "$CYAN" "$RESET" "$*"; }

# IMPORTANT: prompts go to stderr because this function is used as
# command substitution: answer="$(ask_yes_no ...)". Without this,
# the prompt is captured and is invisible on OpenWrt BusyBox shells.
ask_yes_no() {
    question="$1"
    default="$2"
    number="$3"

    while :; do
        if [ "$default" = "Y" ]; then
            printf '\n[%s] %s [Y/n]: ' "$number" "$question" >&2
        else
            printf '\n[%s] %s [y/N]: ' "$number" "$question" >&2
        fi
        IFS= read -r answer
        [ -z "$answer" ] && answer="$default"
        case "$answer" in
            y|Y|yes|YES|Yes|yEs|yeS|YEs|YeS|yES)
                printf '1\n'
                return 0
                ;;
            n|N|no|NO|No|nO|No|NO)
                printf '0\n'
                return 0
                ;;
            *)
                printf 'Please enter Y or N.\n' >&2
                ;;
        esac
    done
}

ask_number() {
    label="$1"
    default="$2"
    min="$3"
    max="$4"
    number="$5"

    while :; do
        printf '\n[%s] %s [%s]: ' "$number" "$label" "$default" >&2
        IFS= read -r value
        [ -z "$value" ] && value="$default"

        case "$value" in
            ''|*[!0-9]*)
                printf 'Please enter a whole number.\n' >&2
                continue
                ;;
        esac

        if [ "$value" -lt "$min" ] 2>/dev/null; then
            printf 'Value must be at least %s.\n' "$min" >&2
            continue
        fi
        if [ -n "$max" ] && [ "$value" -gt "$max" ] 2>/dev/null; then
            printf 'Value must be no more than %s.\n' "$max" >&2
            continue
        fi
        printf '%s\n' "$value"
        return 0
    done
}

ask_text() {
    label="$1"
    number="$2"
    printf '\n[%s] %s: ' "$number" "$label" >&2
    IFS= read -r value
    printf '%s\n' "$value"
}

pause_enter() {
    printf '\nPress ENTER to continue...' >&2
    IFS= read -r dummy
}

if [ "$(id -u)" != "0" ]; then
    err "This script must be run as root."
    exit 1
fi

clear 2>/dev/null
printf '%s\n' '=============================================='
printf ' %sWireGuard Guardian%s\n' "$CYAN" "$RESET"
printf ' Interactive Installer for OpenWrt 25.12.x\n'
printf '%s\n' '=============================================='
echo

# ------------------------------------------------------------
# Detect WireGuard interface
# ------------------------------------------------------------
WG_IF=""
for section in $(uci show network 2>/dev/null | sed -n "s/^network\.\([^.=]*\)\.proto='wireguard'.*/\1/p"); do
    if [ -n "$section" ]; then
        WG_IF="$section"
        break
    fi
done

if [ -z "$WG_IF" ] && [ "$(uci -q get network.wg0.proto 2>/dev/null)" = "wireguard" ]; then
    WG_IF="wg0"
fi

if [ -z "$WG_IF" ]; then
    err "No WireGuard interface was detected."
    echo
    echo "Check with:"
    echo "  uci show network | grep wireguard"
    exit 1
fi
ok "WireGuard interface detected: $WG_IF"

# ------------------------------------------------------------
# Detect WAN interface
# ------------------------------------------------------------
WAN_IF="$(ubus call network.interface.wan status 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)"
if [ -z "$WAN_IF" ]; then
    WAN_IF="$(ip route show default 2>/dev/null | awk 'NR==1 {for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')"
fi

if [ -n "$WAN_IF" ]; then
    ok "WAN interface detected: $WAN_IF"
else
    warn "WAN interface could not be automatically detected."
    WAN_IF=""
fi

echo
echo 'The installer will now ask which features you want.'
echo 'Every question is numbered and remains visible.'
echo 'Press ENTER to accept the recommended default.'
echo

# ------------------------------------------------------------
# Feature configuration
# ------------------------------------------------------------
ENABLE_ROUTE="$(ask_yes_no 'Enable WAN vs WireGuard route detection?' 'Y' '1/10')"
ENABLE_ENDPOINT="$(ask_yes_no 'Enable WireGuard endpoint route check?' 'Y' '2/10')"
ENABLE_RETRY="$(ask_yes_no 'Enable handshake retry/backoff?' 'Y' '3/10')"
ENABLE_DNS="$(ask_yes_no 'Enable DNS health check?' 'Y' '4/10')"
ENABLE_NTP="$(ask_yes_no 'Enable automatic NTP recovery?' 'Y' '5/10')"
ENABLE_FALLBACK="$(ask_yes_no 'Enable boot timeout + safe WAN fallback?' 'Y' '6/10')"
ENABLE_IPV6="$(ask_yes_no 'Disable IPv6 completely?' 'Y' '7/10')"
ENABLE_STATE="$(ask_yes_no 'Enable uptime/state tracking?' 'Y' '8/10')"
ENABLE_TELEGRAM="$(ask_yes_no 'Enable Telegram notifications?' 'N' '9/10')"
ENABLE_BACKUP="$(ask_yes_no 'Enable automatic configuration backups?' 'Y' '10/10')"

# ------------------------------------------------------------
# Advanced settings
# ------------------------------------------------------------
echo
echo '=============================================='
echo ' Advanced Settings'
echo '=============================================='

echo 'Use ENTER for the recommended value.'
WAN_TIMEOUT="$(ask_number 'WAN timeout in seconds' '120' '10' '3600' '1/5')"
NTP_TIMEOUT="$(ask_number 'NTP timeout in seconds' '120' '10' '3600' '2/5')"
HANDSHAKE_TIMEOUT="$(ask_number 'Handshake timeout in seconds' '180' '5' '3600' '3/5')"
WATCHDOG_INTERVAL="$(ask_number 'Watchdog check interval in seconds' '60' '10' '3600' '4/5')"
BACKUP_RETENTION="$(ask_number 'Backup retention count' '5' '1' '100' '5/5')"

TELEGRAM_TOKEN=""
TELEGRAM_CHAT=""
if [ "$ENABLE_TELEGRAM" = "1" ]; then
    echo
echo '=============================================='
    echo ' Telegram Configuration'
    echo '=============================================='
    TELEGRAM_TOKEN="$(ask_text 'Telegram Bot Token' '1/2')"
    TELEGRAM_CHAT="$(ask_text 'Telegram Chat ID' '2/2')"
    if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_CHAT" ]; then
        warn 'Telegram information incomplete. Telegram will be disabled.'
        ENABLE_TELEGRAM="0"
    fi
fi

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
yn() { [ "$1" = "1" ] && printf 'YES' || printf 'NO'; }

echo
echo '=============================================='
echo ' Configuration Summary'
echo '=============================================='
echo
printf '%-32s : %s\n' 'WireGuard interface' "$WG_IF"
printf '%-32s : %s\n' 'WAN interface' "${WAN_IF:-AUTO}"
echo
printf '%-32s : %s\n' 'WAN/WG route detection' "$(yn "$ENABLE_ROUTE")"
printf '%-32s : %s\n' 'Endpoint route check' "$(yn "$ENABLE_ENDPOINT")"
printf '%-32s : %s\n' 'Handshake retry/backoff' "$(yn "$ENABLE_RETRY")"
printf '%-32s : %s\n' 'DNS health check' "$(yn "$ENABLE_DNS")"
printf '%-32s : %s\n' 'Automatic NTP recovery' "$(yn "$ENABLE_NTP")"
printf '%-32s : %s\n' 'Boot timeout/fallback' "$(yn "$ENABLE_FALLBACK")"
printf '%-32s : %s\n' 'IPv6 completely disabled' "$(yn "$ENABLE_IPV6")"
printf '%-32s : %s\n' 'State tracking' "$(yn "$ENABLE_STATE")"
printf '%-32s : %s\n' 'Telegram notifications' "$(yn "$ENABLE_TELEGRAM")"
printf '%-32s : %s\n' 'Automatic backups' "$(yn "$ENABLE_BACKUP")"
echo
printf '%-32s : %s seconds\n' 'WAN timeout' "$WAN_TIMEOUT"
printf '%-32s : %s seconds\n' 'NTP timeout' "$NTP_TIMEOUT"
printf '%-32s : %s seconds\n' 'Handshake timeout' "$HANDSHAKE_TIMEOUT"
printf '%-32s : %s seconds\n' 'Watchdog interval' "$WATCHDOG_INTERVAL"
printf '%-32s : %s\n' 'Backup retention' "$BACKUP_RETENTION"
echo

confirm="$(ask_yes_no 'Proceed with installation?' 'Y' 'CONFIRM')"
if [ "$confirm" != "1" ]; then
    warn 'Installation cancelled. No changes were made.'
    exit 0
fi

# ------------------------------------------------------------
# Create directories and backup
# ------------------------------------------------------------
mkdir -p "$BASE" "$BACKUP_DIR"
chmod 700 "$BASE" "$BACKUP_DIR"

if [ "$ENABLE_BACKUP" = "1" ]; then
    FIRST_BACKUP="$BACKUP_DIR/before-install-$(date +%Y%m%d-%H%M%S).tar.gz"
    tar -czf "$FIRST_BACKUP" /etc/config/network /etc/config/firewall /etc/config/dhcp /etc/config/system /etc/sysctl.conf 2>/dev/null
    if [ -f "$FIRST_BACKUP" ]; then
        chmod 600 "$FIRST_BACKUP"
        ok 'Pre-install configuration backup created.'
    else
        warn 'Could not create pre-install backup.'
    fi
fi

# ------------------------------------------------------------
# Save configuration
# ------------------------------------------------------------
cat > "$CONFIG" <<EOF_CONFIG
# WireGuard Guardian Configuration
WG_IF="$WG_IF"
WAN_IF="$WAN_IF"
ENABLE_ROUTE="$ENABLE_ROUTE"
ENABLE_ENDPOINT="$ENABLE_ENDPOINT"
ENABLE_RETRY="$ENABLE_RETRY"
ENABLE_DNS="$ENABLE_DNS"
ENABLE_NTP="$ENABLE_NTP"
ENABLE_FALLBACK="$ENABLE_FALLBACK"
ENABLE_IPV6="$ENABLE_IPV6"
ENABLE_STATE="$ENABLE_STATE"
ENABLE_TELEGRAM="$ENABLE_TELEGRAM"
ENABLE_BACKUP="$ENABLE_BACKUP"
WAN_TIMEOUT="$WAN_TIMEOUT"
NTP_TIMEOUT="$NTP_TIMEOUT"
HANDSHAKE_TIMEOUT="$HANDSHAKE_TIMEOUT"
WATCHDOG_INTERVAL="$WATCHDOG_INTERVAL"
BACKUP_RETENTION="$BACKUP_RETENTION"
TELEGRAM_TOKEN="$TELEGRAM_TOKEN"
TELEGRAM_CHAT="$TELEGRAM_CHAT"
DNS_TEST_DOMAIN="openwrt.org"
DNS_TEST_IP="1.1.1.1"
EOF_CONFIG
chmod 600 "$CONFIG"

# ------------------------------------------------------------
# Disable automatic WireGuard startup
# ------------------------------------------------------------
uci set network."$WG_IF".auto='0'
uci commit network
ok 'WireGuard automatic boot startup disabled.'
info 'Guardian will start WireGuard after its checks.'

# ------------------------------------------------------------
# Optional IPv6 disable
# ------------------------------------------------------------
if [ "$ENABLE_IPV6" = "1" ]; then
    info 'Disabling IPv6...'
    for file in /proc/sys/net/ipv6/conf/all/disable_ipv6 /proc/sys/net/ipv6/conf/default/disable_ipv6 /proc/sys/net/ipv6/conf/lo/disable_ipv6; do
        [ -f "$file" ] && echo 1 > "$file" 2>/dev/null
    done
    touch /etc/sysctl.conf
    sed -i '/# WG-GUARDIAN-IPV6-START/,/# WG-GUARDIAN-IPV6-END/d' /etc/sysctl.conf
    cat >> /etc/sysctl.conf <<'EOF_IPV6'
# WG-GUARDIAN-IPV6-START
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
# WG-GUARDIAN-IPV6-END
EOF_IPV6
    command -v sysctl >/dev/null 2>&1 && sysctl -p /etc/sysctl.conf >/dev/null 2>&1
    uci set network.lan.ip6assign='0' 2>/dev/null
    uci -q get network.wan6 >/dev/null 2>&1 && uci set network.wan6.disabled='1'
    uci set dhcp.lan.ra='disabled' 2>/dev/null
    uci set dhcp.lan.dhcpv6='disabled' 2>/dev/null
    uci set dhcp.lan.ndp='disabled' 2>/dev/null
    uci commit network
    uci commit dhcp 2>/dev/null
    ok 'IPv6 disabled.'
else
    info 'IPv6 was left unchanged.'
fi

# ------------------------------------------------------------
# Generate runtime guardian
# ------------------------------------------------------------
cat > "$RUNTIME" <<'EOF_RUNTIME'
#!/bin/sh

APP="wg-guardian"
BASE="/etc/wg-guardian"
CONFIG="$BASE/config"
STATE="$BASE/state"
BACKUP_DIR="$BASE/backups"
LOGTAG="wg-guardian"

[ -f "$CONFIG" ] || exit 1
. "$CONFIG"

log() { logger -t "$LOGTAG" "$*"; }
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

set_state() {
    [ "$ENABLE_STATE" = "1" ] || return 0
    cat > "$STATE" <<EOF_STATE
STATE="$1"
REASON="$2"
TIME="$(timestamp)"
WG_IF="$WG_IF"
WAN_IF="$WAN_IF"
UPTIME="$(cut -d. -f1 /proc/uptime 2>/dev/null)"
EOF_STATE
    chmod 600 "$STATE"
}

detect_wan() {
    [ -n "$WAN_IF" ] && return 0
    WAN_IF="$(ubus call network.interface.wan status 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)"
    [ -n "$WAN_IF" ] || WAN_IF="$(ip route show default 2>/dev/null | awk 'NR==1 {for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')"
}

route_is_wan() {
    target="$1"
    [ "$ENABLE_ROUTE" = "1" ] || return 0
    route="$(ip route get "$target" 2>/dev/null)"
    [ -n "$route" ] || return 1
    echo "$route" | grep -q "dev $WG_IF" && return 1
    if [ -n "$WAN_IF" ]; then
        echo "$route" | grep -q "dev $WAN_IF" || return 1
    fi
    return 0
}

wan_ok() {
    detect_wan
    route_is_wan "$DNS_TEST_IP" || return 1
    ping -c 1 -W 2 "$DNS_TEST_IP" >/dev/null 2>&1
}

dns_ok() {
    [ "$ENABLE_DNS" = "1" ] || return 0
    if command -v nslookup >/dev/null 2>&1; then
        nslookup "$DNS_TEST_DOMAIN" >/dev/null 2>&1 && return 0
    fi
    return 1
}

clock_ok() {
    year="$(date +%Y)"
    case "$year" in
        20[2-9][0-9]|2[1-9][0-9][0-9]) return 0 ;;
    esac
    return 1
}

ntp_recover() {
    [ "$ENABLE_NTP" = "1" ] || return 0
    clock_ok && return 0
    log 'Clock invalid. Restarting NTP.'
    /etc/init.d/sysntpd restart >/dev/null 2>&1
    elapsed=0
    while [ "$elapsed" -lt "$NTP_TIMEOUT" ]; do
        clock_ok && { log "NTP synchronized: $(date)"; return 0; }
        sleep 2
        elapsed=$((elapsed + 2))
        if [ $((elapsed % 15)) -eq 0 ]; then
            /etc/init.d/sysntpd restart >/dev/null 2>&1
        fi
    done
    return 1
}

endpoint_ok() {
    [ "$ENABLE_ENDPOINT" = "1" ] || return 0

    # Prefer UCI because the WireGuard interface may be down when this check runs.
    endpoint_host=""
    for peer in $(uci show network 2>/dev/null | sed -n "s/^network\.$WG_IF\.\.\.peer[0-9]*=wireguard_${WG_IF}_peer[0-9]*//p"); do :; done

    # Get the first configured endpoint_host belonging to the WG interface's peers.
    endpoint_host="$(uci show network 2>/dev/null | awk -F= -v p="network.$WG_IF" '$1 ~ /^network\.[^.]+\.\.\.peer/ {next} $1 ~ /\.endpoint_host$/ {gsub(/^.*\.endpoint_host=/,"",$0); gsub(/^'\''|\''$/,"",$0); print $0; exit}')"

    if [ -z "$endpoint_host" ]; then
        endpoint="$(wg show "$WG_IF" endpoints 2>/dev/null | awk 'NR==1 {print $2; exit}')"
        endpoint_host="$(echo "$endpoint" | sed 's/:[0-9]*$//' | sed 's/^\[//' | sed 's/\]$//')"
    fi

    [ -n "$endpoint_host" ] || return 1

    case "$endpoint_host" in
        *.*|*:* ) target="$endpoint_host" ;;
        *) target="$(nslookup "$endpoint_host" 2>/dev/null | awk '/^Address: / {print $2; exit}')" ;;
    esac
    [ -n "$target" ] || return 1
    route_is_wan "$target"
}

latest_handshake() {
    wg show "$WG_IF" latest-handshakes 2>/dev/null | awk 'BEGIN{max=0} {if($2>max)max=$2} END{print max}'
}

handshake_ok() {
    hs="$(latest_handshake)"
    [ -n "$hs" ] && [ "$hs" != "0" ] || return 1
    now="$(date +%s)"
    age=$((now - hs))
    [ "$age" -ge 0 ] 2>/dev/null || return 1
    [ "$age" -le "$HANDSHAKE_TIMEOUT" ]
}

wait_handshake() {
    elapsed=0
    while [ "$elapsed" -lt "$HANDSHAKE_TIMEOUT" ]; do
        handshake_ok && return 0
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

start_wg() {
    log "Starting WireGuard $WG_IF"
    ifup "$WG_IF" >/dev/null 2>&1 || return 1
    wait_handshake
}

stop_wg() { ifdown "$WG_IF" >/dev/null 2>&1; }

telegram() {
    [ "$ENABLE_TELEGRAM" = "1" ] || return 0
    [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT" ] || return 0
    message="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -sS --max-time 10 -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" --data-urlencode "chat_id=${TELEGRAM_CHAT}" --data-urlencode "text=${message}" >/dev/null 2>&1
        return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q -T 10 -O /dev/null --post-data="chat_id=${TELEGRAM_CHAT}&text=${message}" "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" >/dev/null 2>&1
    fi
}

backup() {
    [ "$ENABLE_BACKUP" = "1" ] || return 0
    mkdir -p "$BACKUP_DIR"
    file="$BACKUP_DIR/backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    tar -czf "$file" /etc/config/network /etc/config/firewall /etc/config/dhcp /etc/config/system /etc/sysctl.conf "$CONFIG" 2>/dev/null || return 1
    chmod 600 "$file"
    count=0
    for f in $(ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null); do
        count=$((count + 1))
        if [ "$count" -gt "$BACKUP_RETENTION" ]; then rm -f "$f"; fi
    done
}

boot() {
    detect_wan
    set_state 'BOOTING' 'Guardian starting'
    log "Guardian boot sequence started: WG=$WG_IF WAN=$WAN_IF"

    elapsed=0
    while [ "$elapsed" -lt "$WAN_TIMEOUT" ]; do
        if wan_ok; then log 'WAN Internet available'; break; fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    if ! wan_ok; then
        log 'WAN timeout'
        set_state 'WAN_FAILED' 'WAN unavailable'
        telegram 'OpenWrt Guardian: WAN unavailable.'
        return 1
    fi

    if [ "$ENABLE_DNS" = "1" ] && ! dns_ok; then
        log 'DNS health check failed'
        telegram 'OpenWrt Guardian: DNS health check failed.'
    fi

    if ! ntp_recover; then
        log 'NTP recovery failed'
        set_state 'NTP_FAILED' 'NTP unavailable'
        telegram 'OpenWrt Guardian: NTP synchronization failed.'
        [ "$ENABLE_FALLBACK" = "1" ] && return 1
    fi

    if [ "$ENABLE_ENDPOINT" = "1" ]; then
        if endpoint_ok; then log 'WireGuard endpoint route OK'; else log 'WireGuard endpoint route check failed'; fi
    fi

    attempt=1
    while [ "$attempt" -le 3 ]; do
        log "WireGuard attempt $attempt/3"
        if start_wg; then
            set_state 'RUNNING' 'WireGuard handshake OK'
            log 'WireGuard UP'
            telegram "OpenWrt Guardian: WireGuard UP on $WG_IF"
            return 0
        fi
        stop_wg
        [ "$ENABLE_RETRY" = "1" ] || break
        case "$attempt" in 1) delay=5;; 2) delay=15;; *) delay=30;; esac
        log "Retrying WireGuard in ${delay}s"
        sleep "$delay"
        attempt=$((attempt + 1))
    done

    set_state 'VPN_FAILED' 'WireGuard handshake failed'
    log 'WireGuard startup failed; WAN remains available because WG is not auto-started.'
    telegram "OpenWrt Guardian: WireGuard FAILED on $WG_IF"
    [ "$ENABLE_FALLBACK" = "1" ] && log 'Safe WAN fallback active'
    return 1
}

watchdog() {
    log 'Watchdog started'
    while :; do
        sleep "$WATCHDOG_INTERVAL"
        detect_wan

        if ! wan_ok; then
            set_state 'WAN_DOWN' 'WAN unavailable'
            log 'WAN unavailable'
            continue
        fi

        if ! clock_ok; then
            log 'Clock invalid'
            ntp_recover
            continue
        fi

        if [ "$ENABLE_DNS" = "1" ] && ! dns_ok; then
            log 'DNS health check failed'
            telegram 'OpenWrt Guardian: DNS health check failed.'
        fi

        if handshake_ok; then
            set_state 'RUNNING' 'WireGuard healthy'
            continue
        fi

        log 'WireGuard handshake missing/stale; recovery started'
        set_state 'RECOVERING' 'Handshake failed'
        telegram 'OpenWrt Guardian: WireGuard handshake lost. Recovery started.'
        ntp_recover
        [ "$ENABLE_ENDPOINT" = "1" ] && endpoint_ok

        attempt=1
        recovered=0
        while [ "$attempt" -le 3 ]; do
            stop_wg
            sleep 2
            if start_wg; then
                recovered=1
                set_state 'RUNNING' 'WireGuard recovered'
                log 'WireGuard recovered'
                telegram 'OpenWrt Guardian: WireGuard recovered.'
                break
            fi
            [ "$ENABLE_RETRY" = "1" ] || break
            case "$attempt" in 1) delay=5;; 2) delay=15;; *) delay=30;; esac
            sleep "$delay"
            attempt=$((attempt + 1))
        done

        if [ "$recovered" != "1" ]; then
            set_state 'VPN_FAILED' 'Recovery failed'
            log 'WireGuard recovery failed; WAN remains available.'
            telegram 'OpenWrt Guardian: WireGuard recovery FAILED.'
            sleep 300
        fi
    done
}

status() {
    detect_wan
    echo
    echo '========================================'
    echo ' WireGuard Guardian Status'
    echo '========================================'
    echo
    echo "WireGuard : $WG_IF"
    echo "WAN       : $WAN_IF"
    echo "Time      : $(date)"
    echo
    echo 'Configuration:'
    echo "  Route detection : $ENABLE_ROUTE"
    echo "  Endpoint check  : $ENABLE_ENDPOINT"
    echo "  Retry/backoff   : $ENABLE_RETRY"
    echo "  DNS check       : $ENABLE_DNS"
    echo "  NTP recovery    : $ENABLE_NTP"
    echo "  Safe fallback   : $ENABLE_FALLBACK"
    echo "  IPv6 disabled   : $ENABLE_IPV6"
    echo "  State tracking  : $ENABLE_STATE"
    echo "  Telegram        : $ENABLE_TELEGRAM"
    echo "  Backup          : $ENABLE_BACKUP"
    echo
    echo 'WAN:'
    wan_ok && echo '  OK' || echo '  FAILED'
    echo
    echo 'DNS:'
    dns_ok && echo '  OK' || echo '  FAILED'
    echo
    echo 'Clock:'
    clock_ok && echo "  OK - $(date)" || echo '  INVALID'
    echo
    echo 'WireGuard:'
    handshake_ok && echo '  HANDSHAKE OK' || echo '  HANDSHAKE FAILED/STALE'
    echo
    echo 'IPv6:'
    [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)" = '1' ] && echo '  DISABLED' || echo '  ENABLED'
    echo
    echo 'State:'
    [ -f "$STATE" ] && cat "$STATE" || echo '  No state recorded'
    echo
    wg show "$WG_IF" 2>/dev/null
    echo
}

test_all() {
    echo
    echo '========================================'
    echo ' WireGuard Guardian Diagnostic'
    echo '========================================'
    echo
    detect_wan
    echo "WireGuard interface: $WG_IF"
    echo "WAN interface: $WAN_IF"
    echo
    echo 'Route to 1.1.1.1:'
    ip route get 1.1.1.1 2>/dev/null
    echo
    echo 'WAN Internet:'
    wan_ok && echo '  PASS' || echo '  FAIL'
    echo
    echo 'DNS:'
    dns_ok && echo '  PASS' || echo '  FAIL'
    echo
    echo 'NTP:'
    clock_ok && echo "  PASS - $(date)" || echo '  FAIL'
    echo
    echo 'Endpoint:'
    endpoint_ok && echo '  PASS' || echo '  FAIL'
    echo
    echo 'WireGuard handshake:'
    handshake_ok && echo '  PASS' || echo '  FAIL'
    echo
}

restore() {
    latest="$(ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -n 1)"
    [ -n "$latest" ] || { echo 'No backup available.'; return 1; }
    echo 'Restoring:'
    echo "$latest"
    tar -xzf "$latest" -C / 2>/dev/null || return 1
    echo
    echo 'Restore completed.'
    echo 'Reboot the router to fully apply the restored configuration.'
}

case "$1" in
    daemon) boot; watchdog ;;
    status) status ;;
    test) test_all ;;
    backup) backup ;;
    restore) restore ;;
    stop) ifdown "$WG_IF" >/dev/null 2>&1 ;;
    *)
        echo 'Usage:'
        echo "  $0 daemon"
        echo "  $0 status"
        echo "  $0 test"
        echo "  $0 backup"
        echo "  $0 restore"
        echo "  $0 stop"
        ;;
esac
EOF_RUNTIME
chmod 755 "$RUNTIME"

# ------------------------------------------------------------
# Create OpenWrt procd service
# ------------------------------------------------------------
cat > "$INIT" <<EOF_INIT
#!/bin/sh /etc/rc.common

START=99
STOP=10
USE_PROCD=1

start_service() {
    procd_open_instance guardian
    procd_set_param command "$RUNTIME" daemon
    procd_set_param respawn 3600 5 5
    procd_close_instance
}

stop_service() {
    "$RUNTIME" stop
}
EOF_INIT
chmod 755 "$INIT"

# ------------------------------------------------------------
# Enable service
# ------------------------------------------------------------
"$INIT" enable

# ------------------------------------------------------------
# Final backup
# ------------------------------------------------------------
if [ "$ENABLE_BACKUP" = "1" ]; then
    "$RUNTIME" backup >/dev/null 2>&1
fi

# ------------------------------------------------------------
# Final information
# ------------------------------------------------------------
echo
echo '=============================================='
printf ' %sInstallation Complete%s\n' "$GREEN" "$RESET"
echo '=============================================='
echo
echo "WireGuard interface : $WG_IF"
echo "WAN interface       : ${WAN_IF:-AUTO}"
echo
echo 'Installed files:'
echo "  $RUNTIME"
echo "  $INIT"
echo "  $CONFIG"
echo
echo 'Useful commands:'
echo "  $RUNTIME status"
echo "  $RUNTIME test"
echo "  $RUNTIME backup"
echo "  $RUNTIME restore"
echo
echo 'Live logs:'
echo "  logread -f -e $LOGTAG"
echo
if [ "$ENABLE_IPV6" = "1" ]; then
    echo 'IPv6: DISABLED'
else
    echo 'IPv6: unchanged'
fi
echo
echo 'Starting guardian...'
echo
"$INIT" start
echo
echo '=============================================='
echo ' Guardian started.'
echo '=============================================='
echo
echo 'Recommended: reboot once and watch:'
echo
echo "  logread -f -e $LOGTAG"
echo
