import subprocess
import sys
import os
import re
from flask import Flask, render_template_string

app = Flask(__name__)

CONFIG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.conf")

# Fallbacks used only if config.conf is missing or a key can't be parsed.
DEFAULT_BANLIST_FILE = "/etc/firewall-ips/banned_ips.txt"
DEFAULT_DASHBOARD_PORT = 5050


def load_config(path):
    """Minimal reader for the shell-style KEY="value" / KEY=value lines in config.conf.

    Deliberately does NOT `source`/exec the file - that would mean running
    arbitrary shell as whatever user starts the dashboard. This just reads
    simple assignments, which is all config.conf actually uses.
    """
    config = {}
    if not os.path.isfile(path):
        return config

    assignment = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)=(.*)$')
    with open(path, "r") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            match = assignment.match(line)
            if not match:
                continue
            key, value = match.group(1), match.group(2).strip()
            # Strip one layer of matching quotes, e.g. "5050" -> 5050
            if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
                value = value[1:-1]
            config[key] = value
    return config


CONFIG = load_config(CONFIG_FILE)

BANLIST_FILE = CONFIG.get("BANLIST_FILE", DEFAULT_BANLIST_FILE)

try:
    DASHBOARD_PORT = int(CONFIG.get("DASHBOARD_PORT", DEFAULT_DASHBOARD_PORT))
except ValueError:
    print(f"[!] DASHBOARD_PORT in {CONFIG_FILE} is not a valid integer; "
          f"defaulting to {DEFAULT_DASHBOARD_PORT}.")
    DASHBOARD_PORT = DEFAULT_DASHBOARD_PORT

HONEYPORTS = [p.strip() for p in CONFIG.get("HONEYPORTS", "").split(",") if p.strip()]
PROTECTED_PORTS = [p.strip() for p in CONFIG.get("PROTECTED_PORTS", "").split(",") if p.strip()]


def check_port_collision():
    """Refuse to start if the dashboard's own port is also a honeyport (issue A3).

    Without this check, visiting the dashboard exactly as documented trips the
    honeypot trap against whoever is viewing it - including the operator, if
    they're accessing it remotely.
    """
    if str(DASHBOARD_PORT) in HONEYPORTS:
        print(
            f"\u274c DASHBOARD_PORT ({DASHBOARD_PORT}) is also listed in HONEYPORTS "
            f"in {CONFIG_FILE}.\n"
            f"   Starting the dashboard on this port means every visit to it - "
            f"including your own - trips the honeypot and results in a ban/alert "
            f"against the viewer's IP.\n"
            f"   Fix: change DASHBOARD_PORT in config.conf, or remove "
            f"{DASHBOARD_PORT} from HONEYPORTS.",
            file=sys.stderr,
        )
        sys.exit(1)

    if str(DASHBOARD_PORT) in PROTECTED_PORTS:
        print(
            f"\u26a0\ufe0f  Note: DASHBOARD_PORT ({DASHBOARD_PORT}) is also listed in "
            f"PROTECTED_PORTS. This isn't dangerous (it just means dashboard "
            f"traffic is rate-limited too) but is worth knowing about.",
            file=sys.stderr,
        )


HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>Firewall Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; background-color: #f4f4f4; padding: 20px; }
        h1 { color: #333; }
        .card { background: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); margin-bottom: 20px; }
        pre { background: #1e1e1e; color: #d4d4d4; padding: 15px; border-radius: 5px; overflow-x: auto; }
        .banned { color: #d9534f; font-weight: bold; }
        .meta { color: #777; font-size: 0.85em; }
    </style>
</head>
<body>
    <h1>🔥 Advanced Firewall & IPS Dashboard</h1>
    <p class="meta">Serving on port {{ port }}</p>

    <div class="card">
        <h2>Active iptables Rules</h2>
        <pre>{{ rules }}</pre>
    </div>

    <div class="card">
        <h2 class="banned">Banned IPs (Persistent)</h2>
        <pre>{{ banned_ips }}</pre>
    </div>
</body>
</html>
"""

@app.route('/')
def dashboard():
    # Get iptables rules
    try:
        rules = subprocess.check_output(['iptables', '-L', '-n', '--line-numbers'], text=True)
    except Exception as e:
        rules = f"Error fetching rules: {str(e)}"

    # Get banned IPs
    if os.path.exists(BANLIST_FILE):
        with open(BANLIST_FILE, 'r') as f:
            banned_ips = f.read()
    else:
        banned_ips = "No ban list file found."

    return render_template_string(HTML_TEMPLATE, rules=rules, banned_ips=banned_ips, port=DASHBOARD_PORT)

if __name__ == '__main__':
    check_port_collision()
    print(f"[+] Starting dashboard on http://0.0.0.0:{DASHBOARD_PORT}")
    app.run(host='0.0.0.0', port=DASHBOARD_PORT)
