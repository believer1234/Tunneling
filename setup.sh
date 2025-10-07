#!/usr/bin/env bash
set -euo pipefail

# ==============================================================
# Cloudflare Tunnel Installer for Kali Linux
# ==============================================================
# - Installs cloudflared
# - Authenticates (interactive or headless)
# - Creates a tunnel and config
# - Sets up persistent systemd service
# ==============================================================

TUNNEL_NAME="kali-tunnel"
CONFIG_PATH="/etc/cloudflared/config.yml"
CREDS_DIR="$HOME/.cloudflared"

echo "==========================================="
echo " Cloudflare Tunnel Setup for Kali Linux"
echo "==========================================="
echo

# Step 1: Install cloudflared
echo "[1/5] Installing cloudflared..."
if ! command -v cloudflared >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y curl gnupg lsb-release apt-transport-https ca-certificates

  if [ ! -f /usr/share/keyrings/cloudflare-main.gpg ]; then
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | gpg --dearmor -o /usr/share/keyrings/cloudflare-main.gpg
  fi
  codename="$(lsb_release -cs || echo bullseye)"
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/ ${codename} main" \
    > /etc/apt/sources.list.d/cloudflare-client.list

  apt-get update -y
  apt-get install -y cloudflared || {
    echo "Fallback: downloading latest .deb"
    wget -q -O /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    apt-get install -y /tmp/cloudflared.deb
  }
else
  echo "cloudflared already installed."
fi

# Step 2: Authentication
echo
echo "[2/5] Authenticating with Cloudflare..."
if [ -n "${DISPLAY-}" ]; then
  cloudflared tunnel login
else
  echo "Headless detected."
  echo "1) In another machine, create a tunnel in Cloudflare dashboard."
  echo "2) Copy the credentials JSON into: $CREDS_DIR/"
  exit 0
fi

# Step 3: Create tunnel
echo
echo "[3/5] Creating tunnel..."
if ! cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
  cloudflared tunnel create "$TUNNEL_NAME"
else
  echo "Tunnel '$TUNNEL_NAME' already exists."
fi

# Step 4: Create config.yml
echo
echo "[4/5] Writing $CONFIG_PATH ..."
mkdir -p /etc/cloudflared
cat > "$CONFIG_PATH" <<EOF
tunnel: $TUNNEL_NAME
# credentials-file: $CREDS_DIR/<tunnel-id>.json

ingress:
  - hostname: example.local
    service: http://localhost:8080
  - service: http_status:404
EOF
chmod 640 "$CONFIG_PATH"
echo "Config written."

# Step 5: Enable service
echo
echo "[5/5] Enabling tunnel service..."
if cloudflared service install; then
  echo "cloudflared systemd service installed."
else
  echo "Creating manual service..."
  cat > /etc/systemd/system/cloudflared.service <<SERVICE
[Unit]
Description=cloudflared tunnel
After=network.target

[Service]
ExecStart=/usr/bin/cloudflared tunnel run --config $CONFIG_PATH --name $TUNNEL_NAME
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
SERVICE
  systemctl daemon-reload
  systemctl enable --now cloudflared
fi

echo
echo "✅ Tunnel setup complete!"
echo "Check service: sudo systemctl status cloudflared"
echo "Logs: sudo journalctl -u cloudflared -f"
