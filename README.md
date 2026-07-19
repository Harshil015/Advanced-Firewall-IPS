# Advanced Linux Firewall & IPS

A Bash/iptables stateful firewall with honeyport-based intrusion detection and automated IP banning. Built to understand how host-level defenses actually work — by building one from scratch, then attacking it.

---

## Results

Across all lab test scenarios — port scans, brute-force attempts, connection floods:

| Metric | Result |
|---|---|
| Intrusion prevention rate | 100% across all scenarios |
| Auto-ban trigger time | Under 10 seconds from first anomalous connection |
| Full Linux host hardening time | Under 30 minutes from clean state |

---

## Why I built this

Understanding how firewalls fail requires understanding how they work from the inside. Rather than configuring an existing tool, I wrote the detection logic, the banning mechanism, and the hardening steps from scratch — then tested the result offensively using nmap, Hydra, and netcat to confirm the detection logic caught what it was supposed to.

The honeyport approach was the most interesting design decision. Instead of matching known attack signatures — which attackers can evade — it watches for connections to ports that legitimate traffic would never touch. Any connection to those ports is suspicious by definition, no signature required.

---

## How it works

**Stateful packet inspection** via iptables conntrack — only established and related connections are permitted inbound. All new inbound connections go through explicit allow rules. A parallel nftables implementation is also available for distros where nftables has replaced iptables as the default.

**Honeyport IDS** — a set of ports are left deliberately open but unserviced. Any connection attempt triggers an immediate log entry and the auto-ban logic.

**Automated IP banning** — a Bash watchdog monitors the iptables log and inserts DROP rules for offending IPs within 10 seconds of detection.

**Rate-limiting** — connection rate limiting drops IPs that exceed the configured threshold per time window, functioning as brute-force protection.

**Geo-IP filtering** — inbound connections can be filtered by originating country, layered on top of the stateful rules.

**Signature-based detection** — hooks into Suricata/Snort for signature-based IDS/IPS alongside the honeyport's behavioral detection.

**Live monitoring** — a lightweight web dashboard surfaces active rules and recent bans at a glance, instead of reading raw logs. Ban thresholds and honeyport definitions are adjustable through a config file rather than hardcoded in the script.

---

## Tech stack

| Component | Tool |
|---|---|
| Scripting | Bash |
| Packet filtering | iptables / netfilter, conntrack |
| Networking | TCP/IP, Linux networking fundamentals |
| Attack simulation | nmap, Hydra, netcat |

---

## Setup

```bash
git clone https://github.com/Harshil015/Advanced-Firewall-IPS.git
cd Advanced-Firewall-IPS
chmod +x firewall.sh
sudo ./firewall.sh
```

Root privileges are required — iptables rules require kernel-level access.

**To reset all rules:**

```bash
sudo iptables -F
sudo iptables -X
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT
```

---

## Testing the detection

**Port scan detection:**
```bash
nmap <target-ip>
```

**Honeyport trigger:**
```bash
nc -zv <target-ip> <honeyport>
```

**Monitor the log in real time:**
```bash
sudo dmesg | grep IPTABLES
```

---

## What this demonstrates

- Stateful firewall rule design and iptables/netfilter fluency
- Threat detection through log analysis and automated response
- Attack surface reduction and host-hardening methodology
- Blue Team and Purple Team thinking — building a defense, then validating it offensively

---

## Limitations

- IPv4 only — no IPv6 rule support
- Bash watchdog must remain running for auto-ban to function
- Ban rules are not persistent across reboots by default — use `iptables-persistent` for permanence

---

## Legal disclaimer

For lab and educational use only. Do not deploy on production systems or any network without proper testing and explicit authorization from the system owner.

---

## Author

**Harshil Makwana** — ECE graduate from SVNIT Surat, building security tools and looking for a first role in penetration testing, VAPT, or SOC.

[linkedin.com/in/harshilmakwana](https://linkedin.com/in/harshilmakwana) · [github.com/Harshil015](https://github.com/Harshil015)
