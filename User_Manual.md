# Advanced Linux Firewall & IPS - User Manual

This manual provides comprehensive instructions on how to install, configure, and use the **Advanced Linux Firewall & IPS**. It is designed for system administrators, security enthusiasts, and pentesters who want host-level defense with automated intrusion prevention.

---

## Table of Contents
1. [Prerequisites & Installation](#1-prerequisites--installation)
2. [Quick Start Guide](#2-quick-start-guide-recommended-setup)
3. [Core Features & Use Cases](#3-core-features--use-cases)
4. [Testing & Attack Scenarios](#4-testing--attack-scenarios)
5. [Operational Management](#5-operational-management)
6. [Troubleshooting & FAQs](#6-troubleshooting--faqs)

---

## 1. Prerequisites & Installation

### System Requirements
*   **OS:** Linux (Tested on Ubuntu 22.04 and Kali Linux)
*   **Permissions:** Root (`sudo`) access
*   **Dependencies:** `iptables`, `dmesg`, `awk`

### Installation Steps
1. Clone the repository:
   ```bash
   git clone https://github.com/Harshil015/Advanced-Firewall-IPS.git
   ```
2. Navigate to the directory:
   ```bash
   cd Advanced-Firewall-IPS
   ```
3. Make the script executable:
   ```bash
   chmod +x firewall.sh
   ```
4. Run the script with root privileges:
   ```bash
   sudo ./firewall.sh
   ```

---

## 2. Quick Start Guide (Recommended Setup)

For optimal security, apply your rules in this specific order. Rule order in `iptables` matters—this sequence ensures legitimate traffic is allowed before malicious traffic is logged and dropped.

1.  **Select Option 1: Enable Stateful Firewall** (Drops all unauthorized inbound traffic).
2.  **Select Option 3: Enable Rate-Limiting** (Protect your active services, like SSH on port 22).
3.  **Select Option 2: Enable Honeyport Auto-Ban** (Set up traps on unused ports).
4.  **Select Option 4: Enable Catch-all Logging** (Log any remaining dropped packets).
5.  **Select Option 5: Start Watchdog Daemon** (Activates the automated banning engine).

---

## 3. Core Features & Use Cases

### Use Case 1: Baseline Server Hardening (Stateful Firewall)
**Menu Option:** `1) Enable Stateful Firewall`

*   **What it does:** Flushes existing rules and sets default policies to `DROP` for inbound and forwarded traffic. It allows outbound traffic and permits already-established connections.
*   **When to use:** Immediately upon logging into a fresh server deployment. 
*   **Effect:** Makes the server invisible to unsolicited inbound probes (like `ping` or random port scans) while allowing you to download updates and browse from the server.

### Use Case 2: Brute-Force Protection (Rate-Limiting)
**Menu Option:** `3) Enable Rate-Limiting`

*   **What it does:** Uses the `hashlimit` module to restrict the number of new connections an IP can make to a specific port per minute.
*   **When to use:** On exposed service ports like SSH (22), RDP (3389), or custom web ports to prevent credential stuffing and brute-force attacks.
*   **How to use:** 
    *   Enter the port to protect (e.g., `22`).
    *   Enter the max connections per minute (e.g., `5`). 
*   **Effect:** If an attacker tries to guess passwords via Hydra, the 6th connection attempt within 60 seconds will be logged and instantly dropped.

### Use Case 3: Intrusion Detection (Honeyports)
**Menu Option:** `2) Enable Honeyport Auto-Ban`

*   **What it does:** Opens a "trap" port. Because no legitimate service runs on this port, any connection attempt is deemed malicious. It logs the attempt and drops the packet.
*   **When to use:** Set up 2 or 3 honeyports on common ports attackers scan for (e.g., `2222`, `8080`, `9999`).
*   **How to use:** Enter a port number that is **not** used by any application on your server.
*   **Effect:** When an attacker runs `nmap` and hits this port, the firewall logs a "HONEYPORT ALERT" with their IP address.

### Use Case 4: Forensic Logging
**Menu Option:** `4) Enable Catch-all Logging`

*   **What it does:** Appends a final rule to the INPUT chain that logs any packet that didn't match the rules above it. Logs are rate-limited to 5 per minute to prevent disk exhaustion (Log DoS).
*   **When to use:** Always, as the last step in firewall configuration.
*   **Effect:** Provides visibility into what traffic is being dropped by your default `DROP` policy.

### Use Case 5: Automated IP Banning (Watchdog Daemon)
**Menu Option:** `5) Start Watchdog Daemon`

*   **What it does:** Spawns a background process that continuously monitors kernel logs (`dmesg -w`). If it detects a "HONEYPORT ALERT" or an "IPTABLES DROP" (from rate-limiting), it extracts the attacker's IP and inserts a hard `DROP` rule at the very top of the INPUT chain.
*   **When to use:** After configuring Honeyports and Rate-limiting. It must be running for automated bans to occur.
*   **Effect:** Converts a *detection* into a *prevention*. The attacker's IP is banned instantly, preventing them from probing other ports.

---

## 4. Testing & Attack Scenarios

To validate your configuration, you can simulate attacks from a secondary machine (attacker box) targeting the protected server.

### Scenario A: Port Scan Detection
1. Ensure the Firewall, Honeyport (e.g., port 2222), and Watchdog are active.
2. From the attacker machine, run:
   ```bash
   nmap -sS <target-ip> -p 2222
   ```
3. **Result:** The connection is dropped. On the target server, check the watchdog log:
   ```bash
   cat /tmp/firewall_watchdog.log
   ```
   You should see `[Watchdog] Banned IP: <attacker-ip>`. The attacker can no longer ping or connect to the server.

### Scenario B: Brute-Force SSH Prevention
1. Ensure Stateful Firewall, Rate-Limiting (port 22, 5/min), and Watchdog are active.
2. From the attacker machine, run a Hydra brute-force attack:
   ```bash
   hydra -l root -P /usr/share/wordlists/rockyou.txt ssh://<target-ip>
   ```
3. **Result:** After 5 rapid connection attempts, Hydra will begin timing out. The target server logs the drops, and the watchdog bans the attacker's IP entirely.

### Scenario C: Honeyport Connection (Netcat)
1. Ensure Honeyport (e.g., port 9999) and Watchdog are active.
2. From the attacker machine, attempt to connect:
   ```bash
   nc <target-ip> 9999
   ```
3. **Result:** The connection hangs and closes. The attacker IP is immediately banned by the watchdog.

---

## 5. Operational Management

### Viewing Active Rules & Bans
**Menu Option:** `7) Show Rules & Status`

Use this frequently to verify your rules are loaded correctly and to see which IPs have been dynamically banned by the watchdog. Banned IPs will appear as `DROP all -- <ip> 0.0.0.0/0` at the very top of the INPUT chain.

### Stopping the Automated Ban Engine
**Menu Option:** `6) Stop Watchdog Daemon`

If you accidentally ban your own IP during testing, you can stop the watchdog to prevent further automatic actions. Note that existing ban rules will remain in `iptables` until manually deleted or the firewall is flushed.

### Full System Reset
**Menu Option:** `8) Flush & Reset Firewall`

*   **What it does:** Stops the Watchdog daemon, flushes all `iptables` rules, deletes custom chains, and resets default policies back to `ACCEPT`.
*   **When to use:** If you lock yourself out of a service, or want to start configuring from a clean slate. 
*   *Warning:* If you are connected via SSH, flushing the firewall will not drop your current session (due to conntrack established rules being flushed, but the connection remains active at the network layer), but it will expose your server to new connections.

---

## 6. Troubleshooting & FAQs

**Q: I locked myself out of SSH! How do I get back in?**
A: Because this is a host-level firewall, you will need out-of-band access. If you are on a cloud provider (AWS, DigitalOcean, Azure), use their web console to log into the server and run Option 8 to flush the firewall.

**Q: The Watchdog isn't banning IPs. Why?**
A: Ensure the watchdog is running (Option 7). Check if your system writes iptables logs to `/var/log/syslog` instead of the kernel ring buffer. The watchdog uses `dmesg -w`. If your system uses `rsyslog` exclusively, you may need to modify the `/tmp/firewall_watchdog.sh` script to `tail -f /var/log/syslog` instead.

**Q: Are the ban rules persistent across reboots?**
A: No. By design, this script applies rules to the live kernel memory. When the server reboots, all rules and bans are cleared. To make them persistent, you must install `iptables-persistent` and run `netfilter-persistent save` after configuring your rules.

**Q: Why am I getting duplicate rules?**
A: The script includes idempotency checks (it checks `iptables -C` before adding a rule). If you are seeing duplicates, ensure you aren't running an older version of the script.

--- 

*Disclaimer: This tool is for educational and lab use. Always test firewall configurations in a non-production environment before deploying to live servers.*
