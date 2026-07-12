import subprocess
from flask import Flask, render_template_string
import os

app = Flask(__name__)

# Read config manually for banlist path
BANLIST_FILE = "/etc/firewall-ips/banned_ips.txt"

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
    </style>
</head>
<body>
    <h1>🔥 Advanced Firewall & IPS Dashboard</h1>
    
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

    return render_template_string(HTML_TEMPLATE, rules=rules, banned_ips=banned_ips)

if __name__ == '__main__':
    # Run on port 8080 so it doesn't conflict with standard web services
    # Use a honeyport other than 8080 if you want to hide this!
    app.run(host='0.0.0.0', port=8080)
