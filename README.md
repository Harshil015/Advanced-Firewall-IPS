# Advanced Linux Firewall & IPS

A Bash/iptables stateful firewall with honeyport-based intrusion detection, automated IP banning, GeoIP blocking, and a web dashboard. Built to understand how host-level defences actually work — by building one from scratch, then attacking it.

---

## Results

Across all lab test scenarios — port scans, brute-force attempts, connection floods:

| Metric | Result |
|---|---|
| Intrusion prevention rate | 100% across all scenarios |
| Auto-ban trigger time | Milliseconds from first anomalous connection |
| Full Linux host hardening time | Under 30 minutes from clean state |

---

## Why I built this

Understanding how firewalls fail requires understanding how they work from the inside. Rather than configuring an existing tool, I wrote the detection logic, the banning mechanism, and the hardening steps from scratch — then tested the result offensively using nmap, Hydra, and netcat to confirm the detection logic caught what it was supposed to.

The honeyport approach was the most interesting design decision. Instead of matching known attack signatures — which attackers can evade — it watches for connections to ports that legitimate traffic would never touch. Any connection to those ports is suspicious by definition, no signature required.

---

## How it works

**Stateful packet inspection** via `conntrack` — only established and related connections are permitted inbound. All new inbound connections go through explicit allow rules.

**Honeyport IDS** — trap ports are left deliberately open but unserviced. Any connection attempt triggers an immediate ban, with no need to wait for a pattern to repeat.

**Automated IP banning** — a Bash watchdog monitors kernel logs (`dmesg`) and inserts DROP rules for offending IPs within milliseconds of detection.

**Rate-limiting** — `hashlimit` drops IPs that exceed a connection threshold per time window, functioning as brute-force protection.

**Geo-IP filtering** — `xtables-addons` blocks traffic by country of origin, layered on top of the stateful rules.

**Persistent bans** — banned IPs are written to a file and automatically re-applied on every reboot, so a restart doesn't reset the ban list.

**Real-time alerting** — Slack and Discord webhooks fire the moment an IP is banned, so the logs don't need to be watched directly.

**Live monitoring** — a lightweight Flask web dashboard shows active rules and banned IPs at a glance.

**nftables support** — a native `.rules` file is included for distros where nftables has replaced iptables as the default.

---

## Tech stack

| Component | Tool |
|---|---|
| Scripting | Bash |
| Packet filtering | iptables / netfilter, conntrack, hashlimit |
| Modern filtering | nftables |
| GeoIP | xtables-addons |
| Dashboard | Python, Flask |
| Alerting | Slack / Discord webhooks, curl |
| Attack simulation | nmap, Hydra, netcat |

---

## Installation & setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Harshil015/Advanced-Firewall-IPS.git
   cd Advanced-Firewall-IPS
   ```

2. **Install system dependencies** (optional, recommended for GeoIP & alerts):
   ```bash
   sudo apt update
   sudo apt install xtables-addons-common geoip-database curl
   ```

3. **Install Python dependencies** (for the web dashboard):
   ```bash
   pip3 install -r requirements.txt
   ```

4. **Configure the firewall** — set honeyports, protected ports, GeoIP preferences, and your Slack webhook URL:
   ```bash
   nano config.conf
   ```

5. **Start the firewall:**
   ```bash
   sudo ./firewall.sh start
   ```

6. **Start the web dashboard** (optional):
   ```bash
   sudo python3 dashboard.py
   ```
   Access it at `http://<your-server-ip>:8080`

---

## Usage

```bash
sudo ./firewall.sh start    # Start the firewall and watchdog
sudo ./firewall.sh stop     # Stop the firewall and flush all rules
sudo ./firewall.sh status   # View active rules and watchdog status
```

---

## Testing the detection

**Port scan detection:**
```bash
nmap -sS <target-ip> -p 2222
```

**Brute-force SSH prevention:**
```bash
hydra -l root -P /usr/share/wordlists/rockyou.txt ssh://<target-ip>
```
The 6th connection attempt is dropped, and the IP is permanently banned.

---

## Project structure

```
firewall.sh       — main Bash engine (CLI: start, stop, status)
config.conf       — central configuration for thresholds and settings
dashboard.py      — Flask web application for monitoring
nftables.rules    — modern equivalent of the iptables rules for newer distros
USER_MANUAL.md    — comprehensive guide and use cases
```

---

## What this demonstrates

- Stateful firewall rule design and iptables/nftables fluency across two generations of Linux packet filtering
- Threat detection through log analysis and automated, alerting-integrated response
- Attack surface reduction and host-hardening methodology
- Blue Team and Purple Team thinking — building a defense, then validating it offensively

---

## Limitations

- IPv4 only — no IPv6 rule support
- Bash watchdog must remain running for auto-ban and alerting to function

---

## Roadmap

- [ ] Suricata/Snort integration for signature-based IDS/IPS
- [ ] Dynamic threat intelligence feed integration (AbuseIPDB)
- [ ] Automated fail2ban rule export

---

## Legal disclaimer

For lab and educational use only. Do not deploy on production systems or any network without proper testing and explicit authorisation from the system owner.

---

## Author

**Harshil Makwana** — ECE graduate from SVNIT Surat, building security tools and looking for a first role in penetration testing, VAPT, or SOC.

[linkedin.com/in/harshilmakwana](https://linkedin.com/in/harshilmakwana) · [github.com/Harshil015](https://github.com/Harshil015)
