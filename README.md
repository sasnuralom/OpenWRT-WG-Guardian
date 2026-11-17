# OpenWrt WG Guardian

[**View the installer script**](https://github.com/sasnuralom/OpenWRT-WG-Guardian/blob/main/openwrt-wg-guardian.sh) · [View the repository](https://github.com/sasnuralom/OpenWRT-WG-Guardian) · [Download the latest script](https://raw.githubusercontent.com/sasnuralom/OpenWRT-WG-Guardian/main/openwrt-wg-guardian.sh)

A lightweight WireGuard boot and recovery manager for OpenWrt. WG Guardian is designed to prevent WireGuard from starting before the router has synchronized its system clock, and to monitor the tunnel after startup.

> **Status: testing / use with care**
>
> This project is intended for OpenWrt 25.12.x and uses BusyBox `ash`, UCI, `ubus`, `procd`, `wg`, and standard OpenWrt network interface commands. Shell syntax validation does not prove correct routing or failover on every router. Test on a device where you have local access and a recoverable configuration backup.

## What it does

- Detects an existing UCI WireGuard interface and the logical WAN interface (`wan`).
- Creates a mandatory pre-install backup before removing old WG Guardian files or changing the WireGuard boot setting.
- Disables automatic startup of the detected WireGuard interface so Guardian can wait for time synchronization first.
- Starts its `procd` service at boot and waits for WAN availability.
- Waits for a valid system clock and a successful NTP synchronization message in the current system log before attempting to start WireGuard.
- Checks WireGuard handshake freshness.
- Attempts to bring WireGuard back up and retries with an increasing delay (up to five minutes).
- If it detects a failed tunnel, it takes the WireGuard interface down so the ordinary WAN default route can be used, provided the existing routing configuration supports that behavior.
- Preserves the existing firewall configuration: the installer does **not** create, edit, or delete firewall zones or forwarding rules.

## What it does not do

The current installer deliberately does not manage your network topology. It does not:

- Create a `vpn` firewall zone or LAN-to-VPN forwarding.
- Change LAN-to-WAN forwarding or firewall policies.
- Create or repair full-tunnel `AllowedIPs` or `route_allowed_ips` settings.
- Add policy-routing rules, mwan3 rules, or custom default routes.
- Guarantee WAN fallback if another policy-routing rule, mwan3 configuration, or a persistent VPN default route prevents WAN from becoming the active default route.
- Guarantee that all LAN devices use the VPN when it is up. That depends on your existing WireGuard and firewall configuration.

For all-LAN full-tunnel operation, your existing OpenWrt configuration must already provide the correct WireGuard peer routes and firewall forwarding. Review and test this before enabling the service.

## Requirements

- OpenWrt 25.12.x (the script is written for POSIX/BusyBox `ash`).
- Root access.
- An existing UCI WireGuard interface.
- An existing logical WAN interface named `wan`.
- `wireguard-tools` (`wg`), `uci`, `ubus`, `jsonfilter`, `ip`, `ifup`, `ifdown`, `logread`, and `nslookup`.
- Working WAN connectivity and an OpenWrt NTP client configuration.

## Installation

You can download the installer directly from the GitHub repository. Connect to the router over SSH and run these commands:

```sh
wget -O /root/openwrt-wg-guardian.sh https://raw.githubusercontent.com/sasnuralom/OpenWRT-WG-Guardian/main/openwrt-wg-guardian.sh
chmod +x /root/openwrt-wg-guardian.sh
/root/openwrt-wg-guardian.sh
```
or
```sh
curl -fsSL https://raw.githubusercontent.com/sasnuralom/OpenWRT-WG-Guardian/main/openwrt-wg-guardian.sh | sh
```
You can also [open the installer source on GitHub](https://github.com/sasnuralom/OpenWRT-WG-Guardian/blob/main/openwrt-wg-guardian.sh) before running it.

The installer detects the first UCI network interface whose protocol is `wireguard`. It also detects the WAN layer-3 device from `network.interface.wan`.

Review the detected interfaces before confirming installation.

## Boot sequence

The intended boot order is:

1. OpenWrt brings up WAN and starts its normal time synchronization service.
2. WG Guardian starts under `procd`.
3. Guardian waits until WAN is up.
4. Guardian waits for a valid clock and a successful NTP synchronization message in the current boot's system log.
5. Guardian brings up the WireGuard interface.
6. Guardian waits for a fresh handshake before considering the VPN healthy.

If NTP synchronization is not confirmed, Guardian keeps waiting and does not intentionally start WireGuard. WAN remains available according to the existing network configuration.

## Failure detection and recovery

The runtime checks the interface and the most recent WireGuard handshake. If the tunnel is considered unhealthy, it attempts to bring the interface up and waits for a recent handshake. Failed attempts are retried with a delay that increases from 15 seconds to a maximum of 300 seconds.

When the tunnel is detected as failed, Guardian attempts to take the WireGuard interface down. This is intended to let the existing WAN default route carry traffic until WireGuard recovers.

**Important limitations to understand before deployment:**

- The current implementation reads the endpoint from `wg show`. If the WireGuard interface is already down, that runtime endpoint information may not be available. Endpoint-DNS checking and recovery should therefore be validated on the exact router and configuration; do not assume endpoint-host monitoring is reliable while the interface is down.
- The current NTP check looks for specific `ntpd` synchronization wording in `logread`. OpenWrt log wording can vary by version and time client. Confirm that your router's successful synchronization message matches the check. Otherwise Guardian may wait indefinitely.
- Handshake freshness is based on the most recent peer handshake. A quiet but healthy tunnel may not generate a new handshake within the configured 180-second threshold. Test with your workload and peer keepalive settings.
- The installer does not implement an independent WAN route pin for the WireGuard endpoint. Ensure the endpoint route goes through WAN and cannot recurse through the WireGuard default route.
- Bringing down `wg0` only provides WAN fallback if the existing routing and firewall setup restores a usable WAN path. Validate actual LAN client traffic, not just router-originated pings.

## Firewall and routing

WG Guardian preserves `/etc/config/firewall` and does not create firewall rules. Before installation, verify that your existing configuration includes:

- A firewall zone covering the WireGuard logical interface.
- LAN-to-VPN forwarding.
- Appropriate masquerading and forwarding for your VPN provider/server topology.
- A valid WAN path for fallback.
- Full-tunnel peer routing if you expect all LAN traffic to use WireGuard.

Do not assume that a `vpn` zone alone forces all LAN traffic through WireGuard. Routing and firewall forwarding must both be correct.

## Backup and recovery

Before cleanup or installation, the installer creates a compressed backup under:

```text
/root/wg-guardian-backups/pre-install-YYYYMMDD-HHMMSS.tar.gz
```

The backup includes selected network, firewall, DHCP, system, sysctl, and previous Guardian files when present.

Keep a copy off the router as well. The archive is a recovery aid, not a complete flash image or a guaranteed full-device rollback.

To inspect backups:

```sh
ls -lh /root/wg-guardian-backups/
```

Do not extract an archive over a live router unless you understand which files it contains. Prefer restoring configuration from a local console or a planned recovery session.

## Useful commands

GitHub automatically displays a **Copy** button on the fenced command blocks below.

Check Guardian status:

```sh
/usr/sbin/wg-guardian status
```

Restart Guardian:

```sh
/etc/init.d/wg-guardian restart
```

Stop Guardian:

```sh
/etc/init.d/wg-guardian stop
```

View Guardian logs:

```sh
logread -e wg-guardian
```

Follow logs live:

```sh
logread -f -e wg-guardian
```

Inspect WireGuard:

```sh
wg show
```

Inspect routes:

```sh
ip -4 route
ip -4 rule
```

## Before relying on it

Test these cases while you have local or serial access to the router:

1. Reboot with WAN available and confirm that NTP synchronization is logged before WireGuard starts.
2. Reboot with WAN unavailable and confirm WireGuard remains down while Guardian waits.
3. Restore WAN and confirm NTP sync and WireGuard startup proceed.
4. Make the VPN peer unavailable and confirm the WireGuard interface is taken down and LAN clients use WAN.
5. Restore the VPN peer and confirm a fresh handshake occurs and LAN traffic returns to VPN.
6. Verify DNS, IPv4, IPv6, and traffic from more than one LAN client.
7. Confirm the endpoint itself is routed through WAN during recovery.

If any test fails, stop the service and restore your saved configuration before using the router as your primary gateway.

## Uninstall

The current installer does not include an automatic uninstaller. To avoid removing unrelated configuration, uninstalling should be done deliberately after reviewing the installed files and restoring the desired WireGuard boot setting from your backup. Do not simply delete `/etc/config/network` or `/etc/config/firewall`.

## Compatibility and contributions

This project targets OpenWrt 25.12.x. Behavior may differ on other releases, with alternative NTP clients, non-standard WAN logical interface names, policy routing, multi-WAN, IPv6, or custom WireGuard setups.

Bug reports should include:

- OpenWrt release and device model.
- `uci show network` with keys and secrets redacted.
- Relevant firewall zone/forwarding configuration.
- `wg show` with public endpoint details redacted if desired.
- `ip -4 route` and `ip -4 rule`.
- `logread -e wg-guardian` and relevant NTP log lines.

Never publish private keys, preshared keys, passwords, API tokens, or full configuration backups in an issue.
