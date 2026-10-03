# OpenWRT WG Guardian

A robust WireGuard boot and recovery guardian for **OpenWrt**.

OpenWRT WG Guardian is designed to prevent a common WireGuard problem on routers: after a power interruption or reboot, WireGuard may start before the system clock is synchronized. If the WireGuard tunnel becomes the default route, this can prevent NTP from reaching the Internet, leaving the router stuck without connectivity.

The guardian controls the startup order and continuously checks the WireGuard connection so the router can recover automatically.

---

## 🚀 Quick Start

### 1. SSH into your OpenWrt router

```bash
ssh root@192.168.1.1
```

Replace `192.168.1.1` with your router's IP address if necessary.

### 2. Download the script

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

The script will detect your OpenWrt networking and WireGuard configuration and then ask you which protection features you want to enable.

You can answer each option interactively.

### 5. Check the guardian status

```bash
/usr/sbin/wg-guardian status
```

### 6. Run a manual health test

```bash
/usr/sbin/wg-guardian test
```

### 7. Watch live guardian logs

```bash
logread -f -e wg-guardian
```

### 8. Reboot and test automatic recovery

```bash
reboot
```

After the router comes back online, check:

```bash
/usr/sbin/wg-guardian status
```

---

# Why OpenWRT WG Guardian?

WireGuard itself is extremely reliable, but router boot timing can create a difficult situation.

A typical problematic boot sequence looks like this:

```text
Router boots
    ↓
Network starts
    ↓
WireGuard starts immediately
    ↓
System clock is not synchronized
    ↓
WireGuard handshake fails
    ↓
WireGuard becomes the default route
    ↓
Internet traffic goes through broken WireGuard
    ↓
NTP cannot reach the Internet
    ↓
Clock cannot synchronize
    ↓
WireGuard remains broken
```

This creates a dependency loop.

OpenWRT WG Guardian changes the startup logic to:

```text
Router boots
    ↓
WAN starts
    ↓
Check real Internet connectivity
    ↓
Synchronize system time
    ↓
Validate WireGuard endpoint route
    ↓
Start WireGuard
    ↓
Wait for handshake
    ↓
Verify tunnel
    ↓
Monitor continuously
```

---

# ✨ Features

OpenWRT WG Guardian provides several optional protection mechanisms.

### Core features

* WireGuard boot protection
* NTP synchronization before WireGuard startup
* WAN route detection
* Internet connectivity verification
* WireGuard endpoint pre-check
* WireGuard handshake verification
* Automatic WireGuard recovery
* Handshake retry and backoff
* DNS health checking
* Automatic NTP recovery
* Boot timeout protection
* Safe fallback behavior
* Optional complete IPv6 disabling
* State tracking
* Telegram notifications
* Automatic configuration backups
* Backup restoration
* OpenWrt `procd` service integration
* OpenWrt `logread` logging
* Interactive first-run configuration

---

# 🧠 How It Works

The guardian operates around the following sequence:

```text
                    ┌──────────────┐
                    │ Router Boot  │
                    └──────┬───────┘
                           │
                           ▼
                    ┌──────────────┐
                    │  WAN Ready   │
                    └──────┬───────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │ Internet Check   │
                  └────────┬─────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │   NTP / Clock    │
                  │    Validation    │
                  └────────┬─────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │ WG Endpoint Test │
                  └────────┬─────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │ Start WireGuard  │
                  └────────┬─────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │ Handshake Check  │
                  └────────┬─────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │ Continuous Check │
                  └────────┬─────────┘
                           │
                 ┌─────────┴─────────┐
                 │                   │
              Healthy              Failed
                 │                   │
                 ▼                   ▼
             Continue           Recovery
                                     │
                                     ▼
                               Restart WG
```

---

# ⚙️ Interactive Configuration

The first time you run the script, it asks which features you want.

The configuration is intentionally interactive so you do not have to edit a large configuration file manually.

Typical options include:

```text
Enable WAN route detection? [Y/n]
Enable WireGuard endpoint check? [Y/n]
Enable handshake retry/backoff? [Y/n]
Enable DNS health check? [Y/n]
Enable automatic NTP recovery? [Y/n]
Enable boot timeout + safe fallback? [Y/n]
Disable IPv6 completely? [Y/n]
Enable state tracking? [Y/n]
Enable Telegram notifications? [y/N]
Enable automatic backups? [Y/n]
```

The script then displays a configuration summary before applying the changes.

You can cancel before anything is modified.

---

# 🌐 WAN Route Detection

One of the most important features is checking whether the router can reach the Internet through the **real WAN interface**, rather than accidentally testing connectivity through WireGuard.

A simple:

```bash
ping 1.1.1.1
```

is not always enough.

If WireGuard owns the default route, the ping may itself travel through the broken WireGuard tunnel.

The guardian therefore checks the routing path before considering the WAN connection healthy.

Conceptually:

```text
Internet Test
      │
      ▼
Which interface will carry the traffic?
      │
      ├── WAN ────────► Valid
      │
      └── WireGuard ──► Do not trust as WAN
```

This helps prevent false-positive connectivity tests.

---

# ⏱️ NTP / Clock Recovery

WireGuard relies on correct system time.

After a power loss, the router may boot with an incorrect clock.

The guardian can wait for the system clock to become valid before starting WireGuard.

The general sequence is:

```text
WAN available
      ↓
Internet available
      ↓
NTP synchronization
      ↓
Clock valid
      ↓
WireGuard allowed to start
```

If NTP fails temporarily, the guardian can retry according to the configured recovery behavior.

---

# 🔐 WireGuard Endpoint Check

Before starting or recovering WireGuard, the guardian can verify that the configured WireGuard endpoint has a usable network route.

This helps detect situations where the VPN server is unreachable because the WAN connection is not ready.

Note that endpoint reachability and WireGuard handshake success are different checks.

```text
Endpoint route available
        ↓
WireGuard starts
        ↓
Handshake verified
```

A server may have a valid route while still refusing or not responding to WireGuard traffic, so the handshake check remains important.

---

# 🤝 Handshake Retry & Backoff

If WireGuard does not establish a handshake immediately, the guardian can retry.

Instead of continuously restarting WireGuard as quickly as possible, retry intervals can progressively increase.

Example:

```text
Attempt 1
   ↓
Wait
   ↓
Attempt 2
   ↓
Wait longer
   ↓
Attempt 3
   ↓
Wait longer
   ↓
Recovery
```

This prevents unnecessary rapid restart loops.

---

# 🧪 DNS Health Check

DNS can fail independently from raw Internet connectivity.

The optional DNS check helps detect situations where:

```text
WAN works
   ↓
IP connectivity works
   ↓
DNS does not work
```

This provides another layer of health validation.

---

# 🛡️ Boot Timeout & Safe Fallback

The guardian can use a boot timeout so that it does not wait forever for a condition that may never happen.

For example:

```text
Boot
 ↓
Wait for WAN
 ↓
Wait for Internet
 ↓
Wait for NTP
 ↓
Wait for WireGuard
 ↓
Timeout
```

When the configured timeout is reached, the guardian follows its safe fallback behavior instead of remaining indefinitely in the startup process.

---

# 🌐 IPv6

IPv6 can be optionally disabled if your WireGuard setup is intended to operate entirely over IPv4.

This option is **disabled/enabled during configuration according to your selection**.

If IPv6 is disabled, the router's IPv6-related networking behavior may change.

Only enable this option if disabling IPv6 is appropriate for your network.

---

# 📊 State Tracking

The guardian can maintain a small state file containing information about its current condition.

Example states:

```text
BOOT
WAN_WAIT
NTP_WAIT
WG_START
WG_HANDSHAKE
HEALTHY
RECOVERY
FALLBACK
```

The purpose is to provide useful state information without continuously creating large log files.

---

# 📝 Logging

The guardian uses OpenWrt's system logging instead of creating a continuously growing custom log file.

View guardian logs with:

```bash
logread -e wg-guardian
```

Follow the logs live:

```bash
logread -f -e wg-guardian
```

This keeps logging integrated with OpenWrt's normal logging system.

---

# 📱 Telegram Notifications

Telegram notifications are optional.

If enabled during configuration, the guardian can notify you about important events such as:

```text
WireGuard started
WireGuard handshake established
WireGuard recovery started
WireGuard recovered
NTP recovery
Safe fallback
```

Telegram configuration is only required if you choose to enable the feature.

---

# 💾 Automatic Backups

The guardian can create backups of relevant configuration before making changes.

Backups are stored under:

```text
/etc/wg-guardian/backups/
```

The purpose is to provide a recovery point if configuration changes need to be reverted.

---

# 🔄 Restore Configuration

If the guardian provides a backup restore operation, use:

```bash
/usr/sbin/wg-guardian restore
```

Follow the interactive prompts to select the backup you want to restore.

Always verify your WireGuard and network configuration after restoring.

---

# 🛠️ Guardian Commands

After installation, the guardian command is available at:

```bash
/usr/sbin/wg-guardian
```

## Show status

```bash
/usr/sbin/wg-guardian status
```

Shows the current guardian state and relevant information.

---

## Run health test

```bash
/usr/sbin/wg-guardian test
```

Runs a manual health check without waiting for the next automatic monitoring cycle.

---

## Create backup

```bash
/usr/sbin/wg-guardian backup
```

Creates a configuration backup.

---

## Restore backup

```bash
/usr/sbin/wg-guardian restore
```

Starts the backup restoration process.

---

## Stop guardian

```bash
/usr/sbin/wg-guardian stop
```

Stops the guardian service when supported by the installed configuration.

---

## Run guardian manually

```bash
/usr/sbin/wg-guardian daemon
```

Runs the guardian daemon directly.

Normally, the OpenWrt service should manage it instead.

---

# 🔧 OpenWrt Service

The guardian integrates with OpenWrt's `procd` service manager.

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

Enable at boot:

```bash
/etc/init.d/wg-guardian enable
```

Disable at boot:

```bash
/etc/init.d/wg-guardian disable
```

---

# 🔍 Checking WireGuard Directly

You can always inspect WireGuard independently of the guardian.

Show WireGuard interfaces:

```bash
wg show
```

Show the WireGuard interface:

```bash
wg show wg0
```

Check the interface:

```bash
ip addr show wg0
```

Check routes:

```bash
ip route
```

Check the WireGuard service/network configuration:

```bash
uci show network | grep -i wireguard
```

---

# 🧪 Testing After Installation

After installation, perform the following test.

### 1. Check status

```bash
/usr/sbin/wg-guardian status
```

### 2. Check WireGuard

```bash
wg show
```

### 3. Check routing

```bash
ip route
```

### 4. Run health test

```bash
/usr/sbin/wg-guardian test
```

### 5. Monitor logs

```bash
logread -f -e wg-guardian
```

### 6. Reboot

```bash
reboot
```

### 7. After reboot, check again

```bash
/usr/sbin/wg-guardian status
```

And:

```bash
wg show
```

---

# 🔄 Recovery Behavior

If WireGuard loses its handshake during normal operation, the guardian can detect the failure and attempt recovery.

The general process is:

```text
WireGuard Healthy
       ↓
Handshake Lost
       ↓
Health Check
       ↓
Recovery Attempt
       ↓
WireGuard Restart
       ↓
Handshake Check
       ↓
     ┌─┴─┐
     │   │
   Pass Fail
     │   │
     ▼   ▼
 Healthy Retry
```

The exact behavior depends on which options were enabled during configuration.

---

# 📁 Configuration Files

Guardian files are stored under:

```text
/etc/wg-guardian/
```

The installation may contain files such as:

```text
/etc/wg-guardian/
├── config
├── state
└── backups/
```

The main executable is:

```text
/usr/sbin/wg-guardian
```

The OpenWrt service is:

```text
/etc/init.d/wg-guardian
```

---

# 🗑️ Uninstall

If you need to remove the guardian, use the uninstall functionality provided by the installed script/service.

Before uninstalling, it is recommended to create a backup:

```bash
/usr/sbin/wg-guardian backup
```

Then disable the service:

```bash
/etc/init.d/wg-guardian disable
```

Stop it:

```bash
/etc/init.d/wg-guardian stop
```

If the installation provides an uninstall command, follow its prompts to remove the guardian components.

---

# ⚠️ Important Notes

### WireGuard configuration

OpenWRT WG Guardian is intended to work with an existing OpenWrt WireGuard configuration.

You should have a working WireGuard configuration before installing the guardian.

---

### Endpoint connectivity

An endpoint route check does not guarantee that the remote WireGuard server will accept packets.

The actual WireGuard handshake is the important final verification.

---

### IPv6

Disabling IPv6 can affect other applications and networks.

Only enable the IPv6-disable option if you intentionally want IPv6 disabled.

---

### Router access

Keep a backup of your OpenWrt configuration before making major networking changes.

If you are testing the guardian remotely, make sure you have an alternative way to access the router in case your VPN configuration becomes unavailable.

---

# 📋 Recommended Installation Test

For a new installation, the following sequence is recommended:

```bash
wget -O /root/openwrt-wg-guardian.sh https://raw.githubusercontent.com/sasnuralom/OpenWRT-WG-Guardian/main/openwrt-wg-guardian.sh
```

```bash
chmod +x /root/openwrt-wg-guardian.sh
```

```bash
/root/openwrt-wg-guardian.sh
```

Then:

```bash
/usr/sbin/wg-guardian status
```

Then:

```bash
/usr/sbin/wg-guardian test
```

Then:

```bash
logread -f -e wg-guardian
```

Finally:

```bash
reboot
```

After reboot:

```bash
/usr/sbin/wg-guardian status
```

---

# 📦 Requirements

* OpenWrt
* WireGuard configured
* Root access
* Working WAN connection
* `wireguard-tools`
* Standard OpenWrt networking utilities

The script is designed for OpenWrt and should not be treated as a generic Linux WireGuard service.

---

# 🧩 Project Structure

The current repository uses a single main script:

```text
OpenWRT-WG-Guardian/
└── openwrt-wg-guardian.sh
```

The script handles the installation and first-run interactive configuration.

---

# 🔗 Repository

GitHub:

https://github.com/sasnuralom/OpenWRT-WG-Guardian

Main script:

https://github.com/sasnuralom/OpenWRT-WG-Guardian/blob/main/openwrt-wg-guardian.sh

Raw installation script:

https://raw.githubusercontent.com/sasnuralom/OpenWRT-WG-Guardian/main/openwrt-wg-guardian.sh

---

# 🎯 Project Goal

OpenWRT WG Guardian is intended to make WireGuard-based OpenWrt routers more resilient to:

* Power interruptions
* Unexpected reboots
* Incorrect system time
* NTP synchronization delays
* WAN startup delays
* WireGuard handshake failures
* Temporary endpoint connectivity problems
* DNS failures
* Tunnel failures after boot

The goal is simple:

```text
WAN first
   ↓
Internet
   ↓
Correct time
   ↓
WireGuard
   ↓
Handshake
   ↓
Continuous monitoring
   ↓
Automatic recovery
```

---

# ❤️ Credits

Created by **Sas Nuralom**.

Repository:

https://github.com/sasnuralom/OpenWRT-WG-Guardian
