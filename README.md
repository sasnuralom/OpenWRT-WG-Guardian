# WireGuard Guardian for OpenWrt

A smart, interactive **WireGuard boot and recovery guardian for OpenWrt**.

WireGuard can fail after a router reboot or power interruption when the tunnel starts before the WAN connection and system clock are ready. This can create a dependency loop where **NTP needs Internet access, while Internet access depends on WireGuard**.

**WireGuard Guardian** solves this by intelligently managing the startup and recovery sequence:

```text
Router Boot
    ↓
WAN Internet
    ↓
DNS Check
    ↓
NTP Synchronization
    ↓
WireGuard Endpoint Check
    ↓
WireGuard Start
    ↓
Handshake Verification
    ↓
VPN Internet
```

If the tunnel later stops responding, the guardian automatically detects the problem and attempts recovery using configurable retry and backoff logic.

---

## Features

* ✅ Interactive first-run configuration
* ✅ Separate installation and configuration
* ✅ Automatically detects WireGuard interface
* ✅ Automatically detects WAN interface
* ✅ WAN vs WireGuard route detection
* ✅ WireGuard endpoint reachability check
* ✅ WireGuard handshake monitoring
* ✅ Configurable handshake retry/backoff
* ✅ DNS health monitoring
* ✅ Automatic NTP synchronization and recovery
* ✅ Boot timeout protection
* ✅ Optional safe WAN fallback
* ✅ Optional complete IPv6 disable
* ✅ Uptime and state tracking
* ✅ Bounded configuration/log storage
* ✅ Optional Telegram notifications
* ✅ Automatic configuration backups
* ✅ Backup restoration
* ✅ OpenWrt `procd` service integration
* ✅ Automatic recovery after VPN failure
* ✅ Manual diagnostic mode
* ✅ No dependency on WireGuard for initial NTP synchronization

---

## Why is this needed?

A typical full-tunnel WireGuard setup uses:

```text
AllowedIPs = 0.0.0.0/0
```

After a power failure, the router may boot in this order:

```text
OpenWrt
   ↓
WireGuard starts
   ↓
WireGuard handshake fails
   ↓
Internet unavailable
   ↓
NTP cannot synchronize
   ↓
System clock remains incorrect
   ↓
WireGuard continues failing
```

WireGuard Guardian changes the startup order:

```text
OpenWrt
   ↓
WAN
   ↓
Internet through WAN
   ↓
NTP
   ↓
Correct system time
   ↓
WireGuard
   ↓
Handshake
   ↓
VPN Internet
```

This prevents the common **WireGuard ↔ NTP boot dependency problem**.

---

# Project Structure

Installation and configuration are intentionally separated.

```text
wg-guardian/
├── install.sh          # Install/remove the Guardian service
├── configure.sh        # Interactive first-run/reconfiguration
├── wg-guardian.sh      # Runtime Guardian
├── uninstall.sh        # Optional complete removal
└── README.md
```

### Why separate them?

`install.sh` only installs the required files and service.

`configure.sh` is responsible for network-related choices.

This means you can safely run:

```bash
./configure.sh
```

again later to change settings without reinstalling the project.

---

# Installation

Copy the project files to your OpenWrt router.

For example:

```bash
scp install.sh configure.sh wg-guardian.sh uninstall.sh root@192.168.1.1:/root/
```

SSH into the router:

```bash
ssh root@192.168.1.1
```

Make the scripts executable:

```bash
chmod +x /root/install.sh
chmod +x /root/configure.sh
chmod +x /root/wg-guardian.sh
chmod +x /root/uninstall.sh
```

## Step 1 — Install

Run:

```bash
/root/install.sh
```

The installer installs the Guardian files and OpenWrt `procd` service.

**Installation does not automatically change your network configuration.**

---

## Step 2 — Configure

Run:

```bash
/root/configure.sh
```

The first-run configuration wizard will detect your WireGuard and WAN interfaces and ask which features you want.

Example:

```text
==============================================
 WireGuard Guardian Configuration
==============================================

WireGuard interface detected: wg0
WAN interface detected: eth0

Enable WAN vs WireGuard route detection? [Y/n]:
Enable WireGuard endpoint reachability check? [Y/n]:
Enable handshake retry/backoff? [Y/n]:
Enable DNS health check? [Y/n]:
Enable automatic NTP recovery? [Y/n]:
Enable boot timeout + safe WAN fallback? [Y/n]:
Disable IPv6 completely? [Y/n]:
Enable uptime/state tracking? [Y/n]:
Enable Telegram notifications? [y/N]:
Enable automatic configuration backups? [Y/n]:
```

Before applying any changes, the wizard displays a configuration summary and asks for confirmation.

If you answer `N` at the confirmation step, no configuration changes are applied.

---

# Reconfigure

You can run the configuration wizard again at any time:

```bash
/root/configure.sh
```

This allows you to change features such as:

* NTP recovery
* DNS monitoring
* Endpoint checking
* Retry/backoff
* IPv6
* Telegram
* Backups
* Safe fallback
* Watchdog interval
* Timeouts

There is no need to reinstall the Guardian.

---

# Recovery Logic

The Guardian doesn't blindly restart WireGuard on a fixed schedule.

It checks the actual state first:

```text
WAN
 │
 ├── DOWN → Wait for WAN
 │
 └── UP
       │
       ▼
     DNS
       │
       ▼
     NTP
       │
       ├── Invalid → Synchronize
       │
       └── Valid
             │
             ▼
       Endpoint Check
             │
             ▼
       WireGuard
             │
             ▼
       Handshake
             │
       ┌─────┴─────┐
       │           │
      OK          FAIL
       │           │
       ▼           ▼
    Running    Retry/Backoff
                   │
                   ▼
              Recovery
```

This reduces unnecessary WireGuard restarts and helps prevent tunnel flapping when the VPN server or ISP is temporarily unavailable.

---

# WAN vs WireGuard Route Detection

This is one of the most important features.

A simple:

```bash
ping 1.1.1.1
```

is not enough when WireGuard owns the default route.

The Guardian checks the routing decision first to make sure the connectivity test is actually using the **WAN interface rather than the WireGuard tunnel**.

Conceptually:

```text
             1.1.1.1
                 │
                 ▼
          Routing decision
                 │
        ┌────────┴────────┐
        │                 │
       WAN                WG
        │                 │
       PASS              FAIL
```

This prevents a broken WireGuard tunnel from incorrectly appearing to have working Internet connectivity.

---

# WireGuard Endpoint Check

Before attempting to establish the VPN, the Guardian can verify that the WireGuard endpoint is reachable through the normal WAN route.

This helps distinguish:

```text
WAN problem
```

from:

```text
VPN endpoint problem
```

from:

```text
WireGuard handshake problem
```

---

# Handshake Retry & Backoff

If the initial handshake fails, the Guardian can retry using configurable delays.

Default behavior:

```text
Attempt 1
   ↓
5 seconds
   ↓
Attempt 2
   ↓
15 seconds
   ↓
Attempt 3
   ↓
30 seconds
```

If recovery still fails, the Guardian waits before attempting another recovery cycle.

This avoids continuously restarting WireGuard when the remote VPN server is temporarily unavailable.

---

# DNS Health Check

The Guardian can independently check DNS health.

This helps identify situations where:

```text
Internet connectivity = OK
DNS = FAILED
```

instead of incorrectly treating the entire WAN connection as broken.

---

# Automatic NTP Recovery

After a power interruption, the router's system clock may initially be incorrect.

The Guardian checks the system clock before starting WireGuard.

If necessary:

```text
WAN Internet
     ↓
NTP
     ↓
Valid system time
     ↓
WireGuard
```

If NTP fails, WireGuard startup can be postponed according to the configured fallback behavior.

The Guardian can also attempt NTP recovery later if the system clock becomes invalid.

---

# Boot Timeout & Safe Fallback

The Guardian can wait for WAN connectivity during startup instead of immediately starting WireGuard.

If WireGuard cannot establish a valid handshake after the configured retries, the Guardian can leave the router on its normal WAN connection rather than repeatedly restarting the VPN.

This behavior is configurable.

---

# IPv6

IPv6 disabling is optional.

If enabled, the configuration system disables IPv6 at the kernel/network level and disables common OpenWrt IPv6 services.

If you use IPv6 on your network, choose:

```text
Disable IPv6 completely? [Y/n]: n
```

If IPv6 is disabled, the Guardian does not depend on IPv6 for its connectivity checks.

---

# State & Uptime Tracking

When enabled, the Guardian maintains a small state file containing information such as:

```text
STATE=RUNNING
REASON=WireGuard healthy
TIME=2026-10-03 14:30:00
WG_IF=wg0
WAN_IF=eth0
UPTIME=12345
```

This makes it easier to determine what happened after a reboot or VPN failure.

---

# Logging

The Guardian uses OpenWrt's built-in `logread` system instead of continuously writing a large standalone log file.

View live Guardian logs:

```bash
logread -f -e wg-guardian
```

Search recent events:

```bash
logread -e wg-guardian
```

This keeps persistent storage usage low and is suitable for embedded routers.

---

# Telegram Notifications

Telegram notifications are optional.

When enabled, the Guardian can notify you about events such as:

```text
🟢 WireGuard UP

🟠 WireGuard handshake lost

🟢 WireGuard recovered

🔴 WireGuard recovery failed

🔴 WAN unavailable

🟠 DNS health check failed

🔴 NTP synchronization failed
```

Telegram is not required for the Guardian to operate.

The Telegram credentials are only configured when Telegram notifications are enabled.

---

# Configuration Backups

When enabled, the Guardian can create backups of important OpenWrt configuration files.

Backups are stored under:

```text
/etc/wg-guardian/backups/
```

The number of retained backups can be configured during setup.

Create a manual backup:

```bash
/usr/sbin/wg-guardian backup
```

Restore the latest backup:

```bash
/usr/sbin/wg-guardian restore
```

---

# Diagnostic Commands

## Status

```bash
/usr/sbin/wg-guardian status
```

Displays:

* WireGuard interface
* WAN interface
* Current system time
* WAN health
* DNS health
* WireGuard handshake
* IPv6 state
* Guardian state
* WireGuard information

---

## Full Diagnostic

```bash
/usr/sbin/wg-guardian test
```

The diagnostic checks:

```text
WireGuard interface
WAN interface
WAN route
WAN Internet
DNS
NTP
WireGuard endpoint
WireGuard handshake
IPv6
```

---

## Live Logs

```bash
logread -f -e wg-guardian
```

---

# OpenWrt Service

The Guardian runs as an OpenWrt `procd` service.

Check the service:

```bash
/etc/init.d/wg-guardian status
```

Start:

```bash
/etc/init.d/wg-guardian start
```

Stop:

```bash
/etc/init.d/wg-guardian stop
```

Restart:

```bash
/etc/init.d/wg-guardian restart
```

The service is configured to start automatically during OpenWrt boot.

---

# Uninstallation

To remove the Guardian:

```bash
/root/uninstall.sh
```

The uninstall process should provide an option to restore the configuration backup before removing the service.

---

# Compatibility

Designed primarily for:

* OpenWrt 25.12.x
* WireGuard
* `luci-proto-wireguard`
* `kmod-wireguard`
* `wireguard-tools`
* OpenWrt `procd`

Primary target:

**ASUS RT-AX53U**

Other OpenWrt devices may work as long as they provide the standard OpenWrt networking, UCI, `ubus`, `procd`, and WireGuard utilities.

---

# Important Notes

WireGuard Guardian manages the **startup and health of the WireGuard interface**.

It does **not** automatically create or modify custom firewall kill-switch rules.

This is intentional because automatically modifying firewall rules can interfere with an existing OpenWrt firewall configuration or custom routing setup.

Before deploying on a production router, review:

```bash
/etc/config/network
/etc/config/firewall
```

If you use custom policy routing, multiple WAN interfaces, mwan3, custom firewall marks, or a WireGuard kill switch, review the generated configuration carefully.

---

# Project Goal

The goal is simple:

> **Make WireGuard survive router reboots, power failures, temporary ISP outages, NTP problems, and temporary VPN failures without requiring manual intervention.**

Instead of assuming that everything is ready when OpenWrt boots, WireGuard Guardian verifies each dependency before moving to the next stage.

```text
WAN
 ↓
Internet
 ↓
DNS
 ↓
NTP
 ↓
Endpoint
 ↓
WireGuard
 ↓
Handshake
 ↓
VPN
```

**WireGuard Guardian — because a reboot shouldn't break your VPN.**

---

## License

Choose a license appropriate for your project before publishing, such as **MIT**, **GPL-3.0**, or **Apache-2.0**.
