#!/bin/sh
#
# ============================================================
# WireGuard Guardian - Interactive Installer
# OpenWrt 25.12.x
# ASUS RT-AX53U
#
# Run:
#   chmod +x wg-guardian.sh
#   ./wg-guardian.sh
#
# Or:
#   sh wg-guardian.sh
#
# ============================================================

APP="wg-guardian"
BASE="/etc/wg-guardian"
CONFIG="$BASE/config"
STATE="$BASE/state"
BACKUP_DIR="$BASE/backups"
RUNTIME="/usr/sbin/wg-guardian"
INIT="/etc/init.d/wg-guardian"

LOGTAG="wg-guardian"

# ============================================================
# Colors
# ============================================================

RED="$(printf '\033[31m')"
GREEN="$(printf '\033[32m')"
YELLOW="$(printf '\033[33m')"
BLUE="$(printf '\033[34m')"
CYAN="$(printf '\033[36m')"
RESET="$(printf '\033[0m')"

# ============================================================
# Helpers
# ============================================================

msg() {
    printf "%s\n" "$*"
}

ok() {
    printf "%s[OK]%s %s\n" "$GREEN" "$RESET" "$*"
}

warn() {
    printf "%s[WARN]%s %s\n" "$YELLOW" "$RESET" "$*"
}

err() {
    printf "%s[ERROR]%s %s\n" "$RED" "$RESET" "$*"
}

info() {
    printf "%s[INFO]%s %s\n" "$CYAN" "$RESET" "$*"
}

ask_yes_no() {
    question="$1"
    default="$2"

    while true; do

        if [ "$default" = "Y" ]; then
            printf "%s [Y/n]: " "$question"
        else
            printf "%s [y/N]: " "$question"
        fi

        read answer

        [ -z "$answer" ] && answer="$default"

        case "$answer" in
            y|Y|yes|YES|Yes)
                echo "1"
                return
                ;;
            n|N|no|NO|No)
                echo "0"
                return
                ;;
            *)
                echo "Please answer Y or N." >&2
                ;;
        esac

    done
}

pause() {
    printf "\nPress ENTER to continue..."
    read dummy
}

# ============================================================
# Root check
# ============================================================

if [ "$(id -u)" != "0" ]; then
    err "This script must be run as root."
    exit 1
fi

# ============================================================
# Header
# ============================================================

clear 2>/dev/null

printf "%s\n" "=============================================="
printf " %sWireGuard Guardian%s\n" "$CYAN" "$RESET"
printf " Interactive Installer for OpenWrt 25.12.x\n"
printf "%s\n" "=============================================="
echo

# ============================================================
# Detect WireGuard
# ============================================================

WG_IF=""

for section in $(uci show network 2>/dev/null | \
    sed -n "s/^network\.\([^.=]*\)\.proto='wireguard'.*/\1/p"); do

    if [ -n "$section" ]; then
        WG_IF="$section"
        break
    fi

done

if [ -z "$WG_IF" ]; then

    if [ "$(uci -q get network.wg0.proto 2>/dev/null)" = "wireguard" ]; then
        WG_IF="wg0"
    fi

fi

if [ -z "$WG_IF" ]; then
    err "No WireGuard interface was detected."
    echo
    echo "Check with:"
    echo "  uci show network | grep wireguard"
    exit 1
fi

ok "WireGuard interface detected: $WG_IF"

# ============================================================
# Detect WAN
# ============================================================

WAN_IF=""

WAN_IF="$(ubus call network.interface.wan status 2>/dev/null | \
    jsonfilter -e '@.l3_device' 2>/dev/null)"

if [ -z "$WAN_IF" ]; then

    WAN_IF="$(ip route show default 2>/dev/null | \
        awk 'NR==1 {
            for(i=1;i<=NF;i++)
                if($i=="dev") {
                    print $(i+1)
                    exit
                }
        }')"

fi

if [ -n "$WAN_IF" ]; then
    ok "WAN interface detected: $WAN_IF"
else
    warn "WAN interface could not be automatically detected."
fi

echo

# ============================================================
# Feature questions
# ============================================================

echo "The installer will now ask which features you want."
echo
echo "Press ENTER to accept the recommended default."
echo

ENABLE_ROUTE="$(ask_yes_no \
    "Enable WAN vs WireGuard route detection?" "Y")"

ENABLE_ENDPOINT="$(ask_yes_no \
    "Enable WireGuard endpoint reachability check?" "Y")"

ENABLE_RETRY="$(ask_yes_no \
    "Enable handshake retry/backoff?" "Y")"

ENABLE_DNS="$(ask_yes_no \
    "Enable DNS health check?" "Y")"

ENABLE_NTP="$(ask_yes_no \
    "Enable automatic NTP recovery?" "Y")"

ENABLE_FALLBACK="$(ask_yes_no \
    "Enable boot timeout + safe WAN fallback?" "Y")"

ENABLE_IPV6="$(ask_yes_no \
    "Disable IPv6 completely?" "Y")"

ENABLE_STATE="$(ask_yes_no \
    "Enable uptime/state tracking?" "Y")"

ENABLE_TELEGRAM="$(ask_yes_no \
    "Enable Telegram notifications?" "N")"

ENABLE_BACKUP="$(ask_yes_no \
    "Enable automatic configuration backups?" "Y")"

echo

# ============================================================
# Advanced settings
# ============================================================

echo "=============================================="
echo " Advanced Settings"
echo "=============================================="
echo

printf "WAN timeout in seconds [120]: "
read WAN_TIMEOUT
[ -z "$WAN_TIMEOUT" ] && WAN_TIMEOUT="120"

printf "NTP timeout in seconds [120]: "
read NTP_TIMEOUT
[ -z "$NTP_TIMEOUT" ] && NTP_TIMEOUT="120"

printf "Handshake timeout in seconds [180]: "
read HANDSHAKE_TIMEOUT
[ -z "$HANDSHAKE_TIMEOUT" ] && HANDSHAKE_TIMEOUT="180"

printf "Watchdog check interval in seconds [60]: "
read WATCHDOG_INTERVAL
[ -z "$WATCHDOG_INTERVAL" ] && WATCHDOG_INTERVAL="60"

printf "Backup retention count [5]: "
read BACKUP_RETENTION
[ -z "$BACKUP_RETENTION" ] && BACKUP_RETENTION="5"

echo

# ============================================================
# Telegram configuration
# ============================================================

TELEGRAM_TOKEN=""
TELEGRAM_CHAT=""

if [ "$ENABLE_TELEGRAM" = "1" ]; then

    echo "=============================================="
    echo " Telegram Configuration"
    echo "=============================================="
    echo

    printf "Telegram Bot Token: "
    read TELEGRAM_TOKEN

    printf "Telegram Chat ID: "
    read TELEGRAM_CHAT

    if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_CHAT" ]; then
        warn "Telegram information incomplete."
        warn "Telegram notifications will be disabled."
        ENABLE_TELEGRAM="0"
    fi

fi

# ============================================================
# Summary
# ============================================================

echo
echo "=============================================="
echo " Configuration Summary"
echo "=============================================="
echo

printf "%-32s : %s\n" \
    "WireGuard interface" "$WG_IF"

printf "%-32s : %s\n" \
    "WAN interface" "${WAN_IF:-AUTO}"

echo

printf "%-32s : %s\n" \
    "WAN/WG route detection" \
    "$([ "$ENABLE_ROUTE" = "1" ] && echo YES || echo NO)"

printf "%-32s : %s\n" \
    "Endpoint reachability" \
    "$([ "$ENABLE_ENDPOINT" = "1" ] && echo YES || echo NO)"

printf "%-32s : %s\n" \
    "Handshake retry/backoff" \
    "$([ "$ENABLE_RETRY" = "1" ] && echo YES || echo NO)"

printf "%-32s : %s\n" \
    "DNS health check" \
    "$([ "$ENABLE_DNS" = "1" ] && echo YES || echo NO)"

printf "%-32s : %s\n" \
    "Automatic NTP recovery" \
    "$([ "$ENABLE_NTP" = "1" ] && echo YES || echo NO)"

printf "%-32s : %s\n" \
    "Boot timeout/fallback" \
    "$([ "$ENABLE_FALLBACK" = "1" ] && echo YES || echo NO)"

printf "%-32s : %s\n" \
    "IPv6 completely disabled" \
    "$([ "$ENABLE_IPV6" = "1" ] && echo YES || echo NO)"

printf "%-32s : %s\n" \
    "State tracking" \
    "$([ "$ENABLE_STATE" = "1" ] && echo YES || echo NO)"

printf "%-32s : %s\n" \
    "Telegram notifications" \
    "$([ "$ENABLE_TELEGRAM" = "1" ] && echo YES || echo NO)"

printf "%-32s : %s\n" \
    "Automatic backups" \
    "$([ "$ENABLE_BACKUP" = "1" ] && echo YES || echo NO)"

echo

printf "%-32s : %s seconds\n" \
    "WAN timeout" "$WAN_TIMEOUT"

printf "%-32s : %s seconds\n" \
    "NTP timeout" "$NTP_TIMEOUT"

printf "%-32s : %s seconds\n" \
    "Handshake timeout" "$HANDSHAKE_TIMEOUT"

printf "%-32s : %s seconds\n" \
    "Watchdog interval" "$WATCHDOG_INTERVAL"

printf "%-32s : %s\n" \
    "Backup retention" "$BACKUP_RETENTION"

echo

confirm="$(ask_yes_no \
    "Proceed with installation?" "Y")"

if [ "$confirm" != "1" ]; then
    echo
    warn "Installation cancelled. No changes were made."
    exit 0
fi

# ============================================================
# Create directories
# ============================================================

mkdir -p "$BASE"
mkdir -p "$BACKUP_DIR"

chmod 700 "$BASE"
chmod 700 "$BACKUP_DIR"

# ============================================================
# Backup current configuration BEFORE modifications
# ============================================================

if [ "$ENABLE_BACKUP" = "1" ]; then

    FIRST_BACKUP="$BACKUP_DIR/before-install-$(date +%Y%m%d-%H%M%S).tar.gz"

    tar -czf "$FIRST_BACKUP" \
        /etc/config/network \
        /etc/config/firewall \
        /etc/config/dhcp \
        /etc/config/system \
        /etc/sysctl.conf \
        2>/dev/null

    if [ -f "$FIRST_BACKUP" ]; then
        chmod 600 "$FIRST_BACKUP"
        ok "Pre-install configuration backup created."
    else
        warn "Could not create pre-install backup."
    fi

fi

# ============================================================
# Save configuration
# ============================================================

cat > "$CONFIG" <<EOF
# ============================================================
# WireGuard Guardian Configuration
# Generated: $(date)
# ============================================================

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

RETRY_1="5"
RETRY_2="15"
RETRY_3="30"
EOF

chmod 600 "$CONFIG"

# ============================================================
# Disable automatic WireGuard startup
# ============================================================

uci set network."$WG_IF".auto='0'
uci commit network

ok "WireGuard automatic boot startup disabled."
info "Guardian will start WireGuard after its checks."

# ============================================================
# IPv6
# ============================================================

if [ "$ENABLE_IPV6" = "1" ]; then

    echo
    info "Disabling IPv6..."

    for file in \
        /proc/sys/net/ipv6/conf/all/disable_ipv6 \
        /proc/sys/net/ipv6/conf/default/disable_ipv6 \
        /proc/sys/net/ipv6/conf/lo/disable_ipv6
    do
        if [ -f "$file" ]; then
            echo 1 > "$file" 2>/dev/null
        fi
    done

    touch /etc/sysctl.conf

    sed -i \
        '/# WG-GUARDIAN-IPV6-START/,/# WG-GUARDIAN-IPV6-END/d' \
        /etc/sysctl.conf

    cat >> /etc/sysctl.conf <<'EOF'

# WG-GUARDIAN-IPV6-START
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
# WG-GUARDIAN-IPV6-END
EOF

    if command -v sysctl >/dev/null 2>&1; then
        sysctl -p /etc/sysctl.conf >/dev/null 2>&1
    fi

    uci set network.lan.ip6assign='0' 2>/dev/null

    if uci -q get network.wan6 >/dev/null 2>&1; then
        uci set network.wan6.disabled='1'
    fi

    uci set dhcp.lan.ra='disabled' 2>/dev/null
    uci set dhcp.lan.dhcpv6='disabled' 2>/dev/null
    uci set dhcp.lan.ndp='disabled' 2>/dev/null

    uci commit network
    uci commit dhcp 2>/dev/null

    ok "IPv6 disabled."

else

    info "IPv6 was left unchanged."

fi

# ============================================================
# Generate runtime guardian
# ============================================================

cat > "$RUNTIME" <<'GUARDIAN'
#!/bin/sh

APP="wg-guardian"
BASE="/etc/wg-guardian"
CONFIG="$BASE/config"
STATE="$BASE/state"
BACKUP_DIR="$BASE/backups"
LOGTAG="wg-guardian"

[ -f "$CONFIG" ] || exit 1

. "$CONFIG"

log() {
    logger -t "$LOGTAG" "$*"
}

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

set_state() {

    [ "$ENABLE_STATE" = "1" ] || return 0

    cat > "$STATE" <<EOF
STATE="$1"
REASON="$2"
TIME="$(timestamp)"
WG_IF="$WG_IF"
WAN_IF="$WAN_IF"
UPTIME="$(cut -d. -f1 /proc/uptime 2>/dev/null)"
EOF

    chmod 600 "$STATE"
}

detect_wan() {

    if [ -n "$WAN_IF" ]; then
        return 0
    fi

    WAN_IF="$(ubus call network.interface.wan status 2>/dev/null | \
        jsonfilter -e '@.l3_device' 2>/dev/null)"

    if [ -z "$WAN_IF" ]; then
        WAN_IF="$(ip route show default 2>/dev/null | \
            awk 'NR==1 {
                for(i=1;i<=NF;i++)
                    if($i=="dev") {
                        print $(i+1)
                        exit
                    }
            }')"
    fi
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

    if ! route_is_wan 1.1.1.1; then
        return 1
    fi

    ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1
}

dns_ok() {

    [ "$ENABLE_DNS" = "1" ] || return 0

    if command -v nslookup >/dev/null 2>&1; then
        nslookup "$DNS_TEST_DOMAIN" >/dev/null 2>&1 && return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -q -T 5 -O /dev/null \
            "https://$DNS_TEST_DOMAIN/" >/dev/null 2>&1 && return 0
    fi

    return 1
}

clock_ok() {

    year="$(date +%Y)"

    case "$year" in
        202[5-9]|20[3-9][0-9])
            return 0
            ;;
    esac

    return 1
}

ntp_recover() {

    [ "$ENABLE_NTP" = "1" ] || return 0

    if clock_ok; then
        return 0
    fi

    log "Clock invalid. Restarting NTP."

    /etc/init.d/sysntpd restart >/dev/null 2>&1

    elapsed=0

    while [ "$elapsed" -lt "$NTP_TIMEOUT" ]; do

        if clock_ok; then
            log "NTP synchronized: $(date)"
            return 0
        fi

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

    endpoint="$(wg show "$WG_IF" endpoints 2>/dev/null | \
        awk 'NR==1 {$1=""; sub(/^ /,""); print}')"

    [ -n "$endpoint" ] || return 1

    host="$(echo "$endpoint" | sed 's/:[0-9]*$//')"

    host="$(echo "$host" | sed 's/^\[//' | sed 's/\]$//')"

    case "$host" in
        *.*)
            target="$host"
            ;;
        *)
            target="$(nslookup "$host" 2>/dev/null | \
                awk '/^Address: / {print $2; exit}')"
            ;;
    esac

    [ -n "$target" ] || return 1

    route_is_wan "$target"
}

latest_handshake() {

    wg show "$WG_IF" latest-handshakes 2>/dev/null |
        awk '
        BEGIN {max=0}
        {
            if($2 > max)
                max=$2
        }
        END {
            print max
        }'
}

handshake_ok() {

    hs="$(latest_handshake)"

    [ -n "$hs" ] || return 1
    [ "$hs" != "0" ] || return 1

    now="$(date +%s)"
    age=$((now - hs))

    [ "$age" -le "$HANDSHAKE_TIMEOUT" ]
}

start_wg() {

    log "Starting WireGuard $WG_IF"

    ifup "$WG_IF" >/dev/null 2>&1

    sleep 3

    handshake_ok
}

stop_wg() {

    ifdown "$WG_IF" >/dev/null 2>&1
}

telegram() {

    [ "$ENABLE_TELEGRAM" = "1" ] || return 0

    [ -n "$TELEGRAM_TOKEN" ] || return 0
    [ -n "$TELEGRAM_CHAT" ] || return 0

    message="$1"

    if command -v curl >/dev/null 2>&1; then

        curl -sS --max-time 10 \
            -X POST \
            "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=${TELEGRAM_CHAT}" \
            --data-urlencode "text=${message}" \
            >/dev/null 2>&1

        return
    fi

    if command -v wget >/dev/null 2>&1; then

        wget -q -T 10 -O /dev/null \
            --post-data="chat_id=${TELEGRAM_CHAT}&text=${message}" \
            "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
            >/dev/null 2>&1

    fi
}

backup() {

    [ "$ENABLE_BACKUP" = "1" ] || return 0

    mkdir -p "$BACKUP_DIR"

    file="$BACKUP_DIR/backup-$(date +%Y%m%d-%H%M%S).tar.gz"

    tar -czf "$file" \
        /etc/config/network \
        /etc/config/firewall \
        /etc/config/dhcp \
        /etc/config/system \
        /etc/sysctl.conf \
        "$CONFIG" \
        2>/dev/null

    chmod 600 "$file"

    # Keep only configured number of backups.
    ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null |
        tail -n +"$((BACKUP_RETENTION + 1))" |
        xargs -r rm -f
}

boot() {

    detect_wan

    set_state "BOOTING" "Guardian starting"

    log "Guardian boot sequence started"
    log "WG=$WG_IF WAN=$WAN_IF"

    # --------------------------------------------------------
    # WAN
    # --------------------------------------------------------

    elapsed=0

    while [ "$elapsed" -lt "$WAN_TIMEOUT" ]; do

        if wan_ok; then
            log "WAN Internet available"
            break
        fi

        sleep 2
        elapsed=$((elapsed + 2))

    done

    if ! wan_ok; then

        log "WAN timeout"

        set_state "WAN_FAILED" "WAN unavailable"

        telegram "🔴 OpenWrt Guardian%0AWAN unavailable."

        return 1
    fi

    # --------------------------------------------------------
    # DNS
    # --------------------------------------------------------

    if [ "$ENABLE_DNS" = "1" ]; then

        if dns_ok; then
            log "DNS health check passed"
        else
            log "DNS health check failed"
            telegram "🟠 OpenWrt Guardian%0ADNS health check failed."
        fi

    fi

    # --------------------------------------------------------
    # NTP
    # --------------------------------------------------------

    if ! ntp_recover; then

        log "NTP recovery failed"

        set_state "NTP_FAILED" "NTP unavailable"

        telegram "🔴 OpenWrt Guardian%0ANTP synchronization failed."

        if [ "$ENABLE_FALLBACK" = "1" ]; then
            return 1
        fi

    fi

    # --------------------------------------------------------
    # Endpoint
    # --------------------------------------------------------

    if [ "$ENABLE_ENDPOINT" = "1" ]; then

        if endpoint_ok; then
            log "WireGuard endpoint route OK"
        else
            log "WireGuard endpoint route check failed"
        fi

    fi

    # --------------------------------------------------------
    # Start WireGuard
    # --------------------------------------------------------

    attempt=1

    while [ "$attempt" -le 3 ]; do

        log "WireGuard attempt $attempt/3"

        if start_wg; then

            set_state "RUNNING" "WireGuard handshake OK"

            log "WireGuard UP"

            telegram \
                "🟢 OpenWrt Guardian%0AWireGuard UP%0AInterface: $WG_IF"

            return 0
        fi

        stop_wg

        if [ "$ENABLE_RETRY" != "1" ]; then
            break
        fi

        case "$attempt" in
            1) delay=5 ;;
            2) delay=15 ;;
            3) delay=30 ;;
        esac

        log "Retrying WireGuard in ${delay}s"

        sleep "$delay"

        attempt=$((attempt + 1))

    done

    # --------------------------------------------------------
    # Failed
    # --------------------------------------------------------

    set_state "VPN_FAILED" "WireGuard handshake failed"

    log "WireGuard startup failed"

    telegram \
        "🔴 OpenWrt Guardian%0AWireGuard FAILED%0AInterface: $WG_IF"

    if [ "$ENABLE_FALLBACK" = "1" ]; then
        log "Safe WAN fallback active"
    fi

    return 1
}

watchdog() {

    log "Watchdog started"

    while true; do

        sleep "$WATCHDOG_INTERVAL"

        detect_wan

        # -----------------------------------------
        # WAN
        # -----------------------------------------

        if ! wan_ok; then

            set_state "WAN_DOWN" "WAN unavailable"

            log "WAN unavailable"

            continue
        fi

        # -----------------------------------------
        # NTP
        # -----------------------------------------

        if ! clock_ok; then

            log "Clock invalid"

            ntp_recover

            continue
        fi

        # -----------------------------------------
        # DNS
        # -----------------------------------------

        if [ "$ENABLE_DNS" = "1" ]; then

            if ! dns_ok; then

                log "DNS health check failed"

                telegram \
                    "🟠 OpenWrt Guardian%0ADNS health check failed."

            fi

        fi

        # -----------------------------------------
        # WireGuard
        # -----------------------------------------

        if handshake_ok; then

            set_state "RUNNING" "WireGuard healthy"

            continue
        fi

        log "WireGuard handshake missing/stale"

        set_state "RECOVERING" "Handshake failed"

        telegram \
            "🟠 OpenWrt Guardian%0AWireGuard handshake lost.%0ARecovery started."

        ntp_recover

        if [ "$ENABLE_ENDPOINT" = "1" ]; then
            endpoint_ok
        fi

        attempt=1

        while [ "$attempt" -le 3 ]; do

            stop_wg

            sleep 2

            if start_wg; then

                set_state "RUNNING" "WireGuard recovered"

                log "WireGuard recovered"

                telegram \
                    "🟢 OpenWrt Guardian%0AWireGuard recovered."

                break
            fi

            if [ "$ENABLE_RETRY" != "1" ]; then
                break
            fi

            case "$attempt" in
                1) delay=5 ;;
                2) delay=15 ;;
                3) delay=30 ;;
            esac

            sleep "$delay"

            attempt=$((attempt + 1))

        done

        if ! handshake_ok; then

            set_state "VPN_FAILED" "Recovery failed"

            log "WireGuard recovery failed"

            telegram \
                "🔴 OpenWrt Guardian%0AWireGuard recovery FAILED."

            # Avoid rapid repeated restart cycles.
            sleep 300

        fi

    done
}

status() {

    detect_wan

    echo
    echo "========================================"
    echo " WireGuard Guardian Status"
    echo "========================================"
    echo

    echo "WireGuard : $WG_IF"
    echo "WAN       : $WAN_IF"
    echo "Time      : $(date)"
    echo

    echo "Configuration:"
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

    echo "WAN:"
    if wan_ok; then
        echo "  OK"
    else
        echo "  FAILED"
    fi

    echo

    echo "DNS:"
    if dns_ok; then
        echo "  OK"
    else
        echo "  FAILED"
    fi

    echo

    echo "Clock:"
    if clock_ok; then
        echo "  OK - $(date)"
    else
        echo "  INVALID"
    fi

    echo

    echo "WireGuard:"
    if handshake_ok; then
        echo "  HANDSHAKE OK"
    else
        echo "  HANDSHAKE FAILED/STALE"
    fi

    echo

    echo "IPv6:"
    if [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)" = "1" ]; then
        echo "  DISABLED"
    else
        echo "  ENABLED"
    fi

    echo

    echo "State:"
    if [ -f "$STATE" ]; then
        cat "$STATE"
    else
        echo "  No state recorded"
    fi

    echo

    echo "WireGuard:"
    wg show "$WG_IF" 2>/dev/null

    echo
}

test_all() {

    echo
    echo "========================================"
    echo " WireGuard Guardian Diagnostic"
    echo "========================================"
    echo

    detect_wan

    echo "WireGuard interface:"
    echo "  $WG_IF"

    echo
    echo "WAN interface:"
    echo "  $WAN_IF"

    echo
    echo "Route to 1.1.1.1:"
    ip route get 1.1.1.1 2>/dev/null

    echo
    echo "WAN Internet:"
    if wan_ok; then
        echo "  PASS"
    else
        echo "  FAIL"
    fi

    echo
    echo "DNS:"
    if dns_ok; then
        echo "  PASS"
    else
        echo "  FAIL"
    fi

    echo
    echo "NTP:"
    if clock_ok; then
        echo "  PASS - $(date)"
    else
        echo "  FAIL"
    fi

    echo
    echo "Endpoint:"
    if endpoint_ok; then
        echo "  PASS"
    else
        echo "  FAIL"
    fi

    echo
    echo "WireGuard handshake:"
    if handshake_ok; then
        echo "  PASS"
    else
        echo "  FAIL"
    fi

    echo
    echo "IPv6:"
    if [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)" = "1" ]; then
        echo "  DISABLED"
    else
        echo "  ENABLED"
    fi

    echo
}

restore() {

    latest="$(ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -n 1)"

    if [ -z "$latest" ]; then
        echo "No backup available."
        return 1
    fi

    echo "Restoring:"
    echo "$latest"

    tar -xzf "$latest" -C / 2>/dev/null

    echo
    echo "Restore completed."
    echo "Reboot the router to fully apply the restored configuration."
}

case "$1" in

    daemon)
        boot
        watchdog
        ;;

    status)
        status
        ;;

    test)
        test_all
        ;;

    backup)
        backup
        ;;

    restore)
        restore
        ;;

    stop)
        ifdown "$WG_IF" >/dev/null 2>&1
        ;;

    *)
        echo "Usage:"
        echo
        echo "  $0 daemon"
        echo "  $0 status"
        echo "  $0 test"
        echo "  $0 backup"
        echo "  $0 restore"
        echo "  $0 stop"
        ;;

esac
GUARDIAN

chmod 755 "$RUNTIME"

# ============================================================
# Create OpenWrt procd service
# ============================================================

cat > "$INIT" <<EOF
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

EOF

chmod 755 "$INIT"

# ============================================================
# Enable service
# ============================================================

"$INIT" enable

# ============================================================
# Final backup
# ============================================================

if [ "$ENABLE_BACKUP" = "1" ]; then

    "$RUNTIME" backup >/dev/null 2>&1

fi

# ============================================================
# Final information
# ============================================================

echo
echo "=============================================="
printf " %sInstallation Complete%s\n" "$GREEN" "$RESET"
echo "=============================================="
echo

echo "WireGuard interface : $WG_IF"
echo "WAN interface       : ${WAN_IF:-AUTO}"
echo

echo "Installed files:"
echo "  $RUNTIME"
echo "  $INIT"
echo "  $CONFIG"
echo

echo "Useful commands:"
echo
echo "  $RUNTIME status"
echo "  $RUNTIME test"
echo "  $RUNTIME backup"
echo "  $RUNTIME restore"
echo
echo "Live logs:"
echo
echo "  logread -f -e $LOGTAG"
echo

if [ "$ENABLE_IPV6" = "1" ]; then
    echo "IPv6: DISABLED"
else
    echo "IPv6: unchanged"
fi

echo

echo "Starting guardian..."
echo

"$INIT" start

echo
echo "=============================================="
echo " Guardian started."
echo "=============================================="
echo
echo "Recommended: reboot once and watch:"
echo
echo "  logread -f -e $LOGTAG"
echo
