# Advanced Linux Firewall & IPS - User Manual

This manual provides comprehensive instructions on how to install, configure, and use the **Advanced Linux Firewall & IPS**. 

---

## Table of Contents
1. [Prerequisites & Installation](#1-prerequisites--installation)
2. [Configuration](#2-configuration)
3. [Usage Commands](#3-usage-commands)
4. [Web Dashboard](#4-web-dashboard)
5. [Testing & Attack Scenarios](#5-testing--attack-scenarios)
6. [Using nftables (Modern Distros)](#6-using-nftables-modern-distros)

---

## 1. Prerequisites & Installation

### System Requirements
*   **OS:** Linux (Ubuntu 22.04, Kali Linux, or any Debian-based distro)
*   **Permissions:** Root (`sudo`) access
*   **Dependencies:** `iptables`, `dmesg`, `curl` (for alerts), `python3-flask` (for dashboard)

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/Harshil015/Advanced-Firewall-IPS.git
   cd Advanced-Firewall-IPS
   ```
2. Install optional packages for full feature support:
   ```bash
   sudo apt update
   sudo apt install python3-flask curl xtables-addons-common geoip-database
   ```

---

## 2. Configuration

Before starting the firewall, edit the `config.conf` file to match your environment. The script reads this file automatically upon startup.

```ini
HONEYPORTS="2222,8080,9999"      # Trap ports
PROTECTED_PORTS="22,80,443"      # Ports to rate-limit
MAX_CONN=5                       # Max connections per minute
GEOIP_BLOCK="CN,RU"              # Block countries (leave empty to disable)
WEBHOOK_URL=""                   # Slack/Discord webhook (leave empty to disable)
BANLIST_FILE="/etc/firewall-ips/banned_ips.txt" # Persistence file
DASHBOARD_PORT=5050              # Port for dashboard.py - must NOT appear in HONEYPORTS
```

> **Important:** `DASHBOARD_PORT` must not be one of the ports listed in `HONEYPORTS`. Honeyports
> are trap ports — any connection to one gets logged and banned automatically. If the dashboard
> shared a port with a honeyport, viewing your own dashboard (including from `127.0.0.1`) would
> trigger that same ban logic against you. `dashboard.py` checks for this at startup and exits
> with an error rather than starting on a colliding port.

---

## 3. Usage Commands

The firewall operates via a standard Command Line Interface (CLI). It does not use an interactive menu; instead, it reads your `config.conf` and applies all rules sequentially to ensure proper ordering.

**Start the Firewall:**
Applies all rules from `config.conf` (Stateful firewall, GeoIP, Honeyports, Rate-limits) and starts the background watchdog daemon.
```bash
sudo ./firewall.sh start
```

**Stop the Firewall:**
Stops the watchdog daemon and flushes all iptables rules (resets to default ACCEPT).
```bash
sudo ./firewall.sh stop
```

**Check Status:**
Displays all active iptables rules and checks if the watchdog daemon is currently running.
```bash
sudo ./firewall.sh status
```

---

## 4. Web Dashboard

To visualize rules and banned IPs without using the terminal:

1. Run the Flask app (requires `pip3 install -r requirements.txt`):
   ```bash
   sudo python3 dashboard.py
   ```
2. Open your browser and navigate to `http://<server-ip>:5050` (or whatever port you set
   `DASHBOARD_PORT` to in `config.conf` — the default is 5050).
3. You will see active iptables rules and the list of persistent banned IPs.

---

## 5. Testing & Attack Scenarios

Simulate attacks from a secondary machine to validate your configuration.

### Scenario A: Honeyport Detection
1. Ensure the firewall is started (`sudo ./firewall.sh start`).
2. From the attacker machine, run:
   ```bash
   nc <target-ip> 2222
   ```
3. **Result:** The connection drops immediately. The target server bans the attacker's IP and sends a Slack alert (if configured). The IP is saved to `/etc/firewall-ips/banned_ips.txt`.

### Scenario B: Brute-Force SSH Prevention
1. Ensure port 22 is in `PROTECTED_PORTS` in `config.conf`.
2. From the attacker machine, run a Hydra brute-force attack:
   ```bash
   hydra -l root -P rockyou.txt ssh://<target-ip>
   ```
3. **Result:** After 5 rapid connection attempts, Hydra will time out. The attacker IP is permanently banned.

---

## 6. Using nftables (Modern Distros)

If you are on a modern distro (Debian 11+, Arch) that defaults to `nftables`:

1. Edit `nftables.rules` to customize your honeyports and protected ports.
2. Apply the rules directly:
   ```bash
   sudo nft -f nftables.rules
   ```
3. (Optional) Populate GeoIP blocking. nftables has no built-in geoip matcher the way
   iptables does via `xtables-addons`, so `nftables.rules` ships with an empty
   `geoip_blocked` set. Populate it from real country CIDR data with:
   ```bash
   sudo ./scripts/populate_geoip_set.sh
   ```
   This reads `GEOIP_BLOCK` from `config.conf` by default (or pass country codes
   directly, e.g. `sudo ./scripts/populate_geoip_set.sh CN RU`), downloads the
   corresponding zone files from [ipdeny.com](https://www.ipdeny.com/ipblocks/), and
   loads them into the set. Re-run it periodically (e.g. via cron) to keep it current.
4. To flush nftables rules:
   ```bash
   sudo nft flush ruleset
   ```

> **Note — behavioral differences from the iptables path:** the two rule sets are
> maintained independently, not generated from one another, and differ in a couple of
> ways worth knowing about:
> - **Ban duration:** iptables (`firewall.sh`) bans are permanent until manually removed
>   from the ban file; nftables (`nftables.rules`) bans expire automatically after 1 hour
>   (`timeout 1h` on the sets). Edit that value if you want different behavior.
> - **Rate limiting:** both rule sets rate-limit ports 22, 80, and 443 at `5/minute` by
>   default, matching `config.conf`'s `MAX_CONN=5`. If you change `MAX_CONN` or
>   `PROTECTED_PORTS` in `config.conf`, remember to update `nftables.rules` by hand too —
>   it won't pick the change up automatically.

---

*Disclaimer: This tool is for educational and lab use. Always test firewall configurations in a non-production environment before deploying to live servers.*
