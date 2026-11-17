# OpenWRT WG Guardian

**OpenWRT WG Guardian** prevents WireGuard NTP/time-synchronization boot issues and automatically manages WAN connectivity, NTP, DNS, tunnel health, and recovery to maintain a reliable VPN connection.

It also includes an independent system recovery mechanism that can restore previous OpenWrt settings—even when WG Guardian is not installed.

---

## 🚀 Quick Start

### 1. Connect to your router

```bash
ssh root@192.168.1.1
```

### 2. Download the installer

```bash
wget -O /root/openwrt-wg-guardian.sh https://raw.githubusercontent.com/sasnuralom/OpenWRT-WG-Guardian/main/openwrt-wg-guardian.sh
```

### 3. Make it executable

```bash
chmod +x /root/openwrt-wg-guardian.sh
```

### 4. Run the installer

```bash
/root/openwrt-wg-guardian.sh
```

The installer automatically:

- Checks for existing recovery backups.
- Detects your WireGuard and WAN interfaces.
- Asks which protection features you want.
- Collects advanced configuration settings.
- Displays a configuration summary.
- Creates a backup before modifying system settings.
- Installs and configures the Guardian service.

### 5. Check installation

```bash
/usr/sbin/wg-guardian status
```

### 6. Run a diagnostic test

```bash
/usr/sbin/wg-guardian test
```

### 7. Monitor logs

```bash
logread -f -e wg-guardian
```

---

## 🆕 What's New: Standalone System Recovery

One of the most important additions is the **Standalone System Recovery** system.

Previously, restoring settings depended on the Guardian installation being available. The new recovery mechanism works independently.

Even if:

- WG Guardian was never installed.
- The installation failed halfway.
- Guardian configuration was deleted.
- The Guardian service is missing.
- You need to recover after a configuration change.

You can launch the installer and access recovery before the normal installation process begins.

### How it works

When existing backups are found, the installer displays:

```text
==============================================
 Standalone System Recovery
==============================================
This recovery works even when WG Guardian is not installed.

1) Continue to installer
2) Restore a previous OpenWrt settings backup
3) Exit

Choose [1-3, default 1]:
```

### Recovery options

| Option | Description |
|---|---|
| 1 | Continue with installation |
| 2 | Browse and restore available backups |
| 3 | Exit without changing settings |

### Restore previous settings

Choose option `2`.

The recovery system will:

1. Search independent and Guardian backup directories.
2. Display available backup archives.
3. Allow you to select a backup.
4. Validate the selected archive.
5. Create a snapshot of current settings.
6. Ask for confirmation.
7. Restore the selected configuration.

After restoration, reboot the router to apply restored network settings.

**Important:** Recovery requires an existing valid backup. It cannot reconstruct settings that were never backed up.

---

## 💾 Independent Backup System

Backups are now stored outside the Guardian installation directory.

<pre>
/root/wg-guardian-backups/
├── pre-install-YYYYMMDD-HHMMSS.tar.gz
├── backup-YYYYMMDD-HHMMSS.tar.gz
└── pre-restore-YYYYMMDD-HHMMSS.tar.gz
</pre>

This means removing `/etc/wg-guardian/` does not automatically remove the independent recovery backups.

### Backup locations

| Location | Purpose |
|---|---|
| `/root/wg-guardian-backups/` | Independent recovery backups |
| `/etc/wg-guardian/backups/` | Guardian-managed backups |

The recovery system checks both locations.

### Create a backup manually

After installation:

```bash
/usr/sbin/wg-guardian backup
```

### Restore a backup after installation

```bash
/usr/sbin/wg-guardian restore
```

### Important backup behavior

Before restoring, the recovery system creates a snapshot of the current configuration so that you have another recovery point.

Keep your independent backup directory safe. Consider copying it to another device for additional protection.

---

## 🛡️ Why OpenWRT WG Guardian?

WireGuard can encounter a boot-time dependency problem after a power interruption or router reboot.

A typical scenario:

```text
Router boots
    ↓
WAN starts
    ↓
WireGuard starts too early
    ↓
System clock is incorrect
    ↓
WireGuard handshake fails
    ↓
VPN becomes the default route
    ↓
NTP cannot reach the Internet
    ↓
System clock cannot synchronize
    ↓
WireGuard remains disconnected
```

This creates a dependency loop between NTP synchronization and WireGuard connectivity.

WG Guardian is designed to manage this startup process:

```text
Router boots
    ↓
WAN connectivity check
    ↓
Internet availability
    ↓
NTP synchronization
    ↓
System clock validation
    ↓
WireGuard endpoint route check
    ↓
WireGuard startup
    ↓
Handshake verification
    ↓
Continuous monitoring
    ↓
Automatic recovery
```

---

## ✨ Features

### WireGuard protection
- Controlled WireGuard startup
- NTP synchronization before WireGuard startup
- Handshake verification
- Automatic tunnel recovery
- Retry and backoff mechanism
- Endpoint route checking

### Network monitoring
- WAN route detection
- Internet connectivity verification
- DNS health checking
- Automatic NTP recovery
- Boot timeout protection
- Safe fallback behavior

### System management
- Optional IPv6 disabling
- Uptime and state tracking
- Telegram notifications
- Automatic configuration backups
- Independent recovery system
- Restore without Guardian installation
- Pre-restore configuration snapshots
- Interactive installation and configuration

### OpenWrt integration
- BusyBox-compatible shell
- `procd` service integration
- `logread` system logging

---

## ⚙️ Interactive Configuration

The installer asks which features you want to enable.

Example:

```text
[1/10] Enable WAN vs WireGuard route detection? [Y/n]:
[2/10] Enable WireGuard endpoint route check? [Y/n]:
[3/10] Enable handshake retry/backoff? [Y/n]:
[4/10] Enable DNS health check? [Y/n]:
[5/10] Enable automatic NTP recovery? [Y/n]:
[6/10] Enable boot timeout + safe WAN fallback? [Y/n]:
[7/10] Disable IPv6 completely? [Y/n]:
[8/10] Enable uptime/state tracking? [Y/n]:
[9/10] Enable Telegram notifications? [y/N]:
[10/10] Enable automatic configuration backups? [Y/n]:
```

Press ENTER to accept the recommended default.

The installer then asks for advanced settings, including:

- WAN timeout
- NTP timeout
- Handshake timeout
- Watchdog interval
- Backup retention count

A configuration summary is displayed before installation.

---

## 🌐 WAN Route Detection

The guardian checks whether Internet traffic is actually using the WAN interface rather than accidentally passing through WireGuard.

A simple ping test can produce misleading results when WireGuard owns the default route.

The guardian checks the route before considering WAN connectivity healthy.

---

## ⏱️ NTP / Clock Recovery

Incorrect system time can prevent successful WireGuard operation.

The guardian checks clock validity and can restart NTP synchronization when necessary.

The intended startup sequence is:

```text
WAN available
    ↓
Internet available
    ↓
NTP synchronization
    ↓
Clock validation
    ↓
WireGuard startup
```

---

## 🔐 WireGuard Endpoint & Handshake Checks

The endpoint route check verifies that the configured endpoint has a usable WAN route.

The handshake check separately verifies whether WireGuard has successfully established communication.

A valid route alone does not guarantee a successful handshake.

---

## 🔄 Automatic Recovery

If the WireGuard handshake becomes stale or disappears, the guardian can attempt recovery.

```text
WireGuard healthy
       ↓
Handshake lost
       ↓
Health check
       ↓
Recovery attempt
       ↓
WireGuard restart
       ↓
Handshake verification
       ↓
Healthy or retry
```

Retry intervals use backoff to avoid unnecessary rapid restart loops.

---

## 📱 Telegram Notifications

Telegram notifications are optional.

When enabled, the guardian can report important events, including:

- WireGuard startup
- Successful handshake
- Recovery started
- Recovery completed
- NTP synchronization problems
- WAN connectivity problems

---

## 🌐 IPv6 Management

IPv6 disabling is optional.

If enabled, the installer applies its IPv6-related configuration changes. This can affect other network services, so review the option carefully before enabling it.

---

## 📊 State Tracking & Logging

The guardian maintains a small state file when state tracking is enabled.

Logs are integrated with OpenWrt's system logger.

View logs:

```bash
logread -e wg-guardian
```

Follow logs live:

```bash
logread -f -e wg-guardian
```

---

## 🛠️ Guardian Commands

### Status

```bash
/usr/sbin/wg-guardian status
```

### Diagnostic test

```bash
/usr/sbin/wg-guardian test
```

### Create backup

```bash
/usr/sbin/wg-guardian backup
```

### Restore backup

```bash
/usr/sbin/wg-guardian restore
```

### Start service

```bash
/etc/init.d/wg-guardian start
```

### Stop service

```bash
/etc/init.d/wg-guardian stop
```

### Restart service

```bash
/etc/init.d/wg-guardian restart
```

### Enable at boot

```bash
/etc/init.d/wg-guardian enable
```

### Disable at boot

```bash
/etc/init.d/wg-guardian disable
```

---

## 🧪 Testing After Installation

Check Guardian status:

```bash
/usr/sbin/wg-guardian status
```

Check WireGuard:

```bash
wg show
```

Check routing:

```bash
ip route
```

Run diagnostics:

```bash
/usr/sbin/wg-guardian test
```

Monitor logs:

```bash
logread -f -e wg-guardian
```

Reboot:

```bash
reboot
```

After reboot, check the status again:

```bash
/usr/sbin/wg-guardian status
```

---

## ⚠️ Important Notes

- An existing WireGuard configuration is required.
- Always keep a backup before making major network changes.
- Independent recovery requires a valid backup archive.
- Restoring network configuration may temporarily interrupt connectivity.
- Reboot after restoring network settings.
- Disabling IPv6 can affect other devices and services.
- When managing the router remotely, maintain an alternative access method.
- A backup created before installing this version may not contain the independent recovery directory.

---

## 📦 Requirements

- OpenWrt 25.12.x
- Root access
- Existing WireGuard configuration
- Working WAN connection
- `wireguard-tools`
- Standard OpenWrt networking utilities

---

## 📁 Project Structure

The repository currently uses a single installer script:

```text
OpenWRT-WG-Guardian/
├── README.md
└── openwrt-wg-guardian.sh
```

The script handles installation, interactive configuration, Guardian setup, and standalone recovery.

---

## 🎯 Project Goal

Make WireGuard-based OpenWrt routers more reliable by addressing:

- NTP synchronization problems during boot
- Incorrect system clock
- WAN startup delays
- WireGuard handshake failures
- DNS and connectivity problems
- Unexpected tunnel disconnections
- Configuration mistakes
- Failed or incomplete Guardian installations

**The core principle:**

```text
WAN → Internet → NTP → WireGuard → Handshake → Monitoring → Recovery
```

And if something goes wrong:

```text
Backup → Independent Recovery → Restore → Reboot
```

---

## 🔗 Repository

**GitHub:** https://github.com/sasnuralom/OpenWRT-WG-Guardian

**Installer:** https://github.com/sasnuralom/OpenWRT-WG-Guardian/blob/main/openwrt-wg-guardian.sh

**Raw script:** https://raw.githubusercontent.com/sasnuralom/OpenWRT-WG-Guardian/main/openwrt-wg-guardian.sh

---

**OpenWRT WG Guardian — Reliable WireGuard connectivity, smarter boot management, and independent system recovery.**
