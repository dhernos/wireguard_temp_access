# Temporary WireGuard Client Provisioning Script

## Overview

This repository contains a Bash script that dynamically creates **temporary WireGuard clients** on a running WireGuard server. Each client:

* Gets a unique `/32` IP address in the `10.2.0.0/16` range
* Is added live via `wg set` (no interface restart)
* Receives an auto-generated WireGuard client configuration
* Is automatically **removed after a defined number of hours**
* Has its configuration file deleted automatically
* Can be onboarded easily via **QR code** (mobile devices)

This is designed for **temporary access** (guests, tablets, contractors, emergency access), not long-lived peers.

---

## Requirements

### Operating System

* Linux (tested on Debian/Ubuntu)
* systemd-based distribution recommended

### Required Packages

Install the following packages before running the script:

```bash
apt update
apt install -y wireguard qrencode at iproute2
```

Ensure the `atd` service is enabled and running:

```bash
systemctl enable --now atd
```

---

## WireGuard Server Prerequisites

This script assumes:

* A **running WireGuard interface** (e.g. `wg2`)
* The interface is already up (`wg-quick up wg2` or systemd service)
* IP forwarding is enabled
* Firewall rules (iptables/nftables) already allow WireGuard traffic

### Example Server Interface Configuration

```ini
[Interface]
Address = 10.2.0.1/16
ListenPort = 51822
PrivateKey = <server-private-key>
```

Enable IP forwarding:

```bash
echo 1 > /proc/sys/net/ipv4/ip_forward
```

Persist it:

```bash
sysctl -w net.ipv4.ip_forward=1
```

---

## Mandatory Script Configuration

Before using the script, you **must** edit these variables:

```bash
WG_INTERFACE="wg2"
SERVER_PUBLIC_KEY="<SERVER_PUBLIC_KEY>"
SERVER_ENDPOINT="vpn.example.com:51822"
SERVER_TUNNEL_IP="10.2.0.1"
```

If these values are wrong, generated clients will not be able to connect.

---

## How It Works (Technical Flow)

1. Script checks for root privileges and required tools
2. A "random" Client IP is derived from current hour and minute (`10.2.H.M`)
3. A WireGuard keypair is generated
4. Peer is added live using `wg set`
5. A static `/32` route is added to the interface
6. Client config is written to disk
7. A cleanup job is scheduled via `at`
8. QR code is generated for easy mobile onboarding
9. After expiration:

   * Peer is removed
   * Route is deleted
   * Config file is deleted

No WireGuard restart is required at any point.

---

## Limitations and Notes

* IP generation is only semi random (**time-based**), not entirely collision-proof under heavy usage
* Only suitable for **low-frequency temporary clients**
* No persistence across server reboots for scheduled `at` jobs
* Not designed as a full IPAM or user management system

If you need scaling, auditing, or persistence, use a proper provisioning system.

---

## Security Considerations

* Config files contain **private keys** (short-lived but sensitive)
* Run the script only on trusted systems
* Limit shell access to the WireGuard host
* Consider placing output configs in a secure directory

---

## License

AGPL-3.0 License. Use at your own risk.

---

## Intended Use Case

This script is intentionally simple and pragmatic.
It is meant for private use for **fast, temporary WireGuard access** without tooling overhead.
