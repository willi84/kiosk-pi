#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SETUP_CONFIG_FILE="$SCRIPT_DIR/kiosk-config.env"

APP_DIR="/opt/kiosk-display"
CONFIG_DIR="/etc/kiosk-display"
CONFIG_FILE="$CONFIG_DIR/config.json"

USER_NAME="${SUDO_USER:-$(whoami)}"

if [ "$USER_NAME" = "root" ]; then
  echo "❌ Bitte nicht direkt als root ausführen. Nutze deinen normalen User."
  exit 1
fi

if [ ! -f "$SETUP_CONFIG_FILE" ]; then
  echo "❌ Config fehlt: $SETUP_CONFIG_FILE"
  echo "➡️ Lege kiosk-config.env neben setup-kiosk.sh an."
  exit 1
fi

# shellcheck disable=SC1090
source "$SETUP_CONFIG_FILE"

KIOSK_HOSTNAME="${KIOSK_HOSTNAME:-kiosk-pi}"
KIOSK_URL="${KIOSK_URL:-https://example.com}"
WIFI_SSID="${WIFI_SSID:-}"
WIFI_PASSWORD="${WIFI_PASSWORD:-}"
WIFI_HIDDEN="${WIFI_HIDDEN:-false}"

echo "== Hostname =="
if [ "$(hostname)" != "$KIOSK_HOSTNAME" ]; then
  sudo hostnamectl set-hostname "$KIOSK_HOSTNAME"
  echo "✅ Hostname gesetzt: $KIOSK_HOSTNAME"
else
  echo "ℹ️ Hostname bereits gesetzt: $KIOSK_HOSTNAME"
fi

echo "== Chromium Paket erkennen =="
if apt-cache show chromium >/dev/null 2>&1; then
  CHROMIUM_PACKAGE="chromium"
  CHROMIUM_CMD="chromium"
elif apt-cache show chromium-browser >/dev/null 2>&1; then
  CHROMIUM_PACKAGE="chromium-browser"
  CHROMIUM_CMD="chromium-browser"
else
  echo "❌ Kein Chromium-Paket gefunden"
  exit 1
fi

echo "✅ Chromium Paket: $CHROMIUM_PACKAGE"
echo "✅ Chromium Command: $CHROMIUM_CMD"

echo "== Installiere Pakete =="
sudo apt update
sudo apt install -y \
  "$CHROMIUM_PACKAGE" \
  unclutter \
  x11-xserver-utils \
  network-manager

echo "== Verzeichnisse =="
sudo mkdir -p "$APP_DIR" "$CONFIG_DIR"

echo "== Kiosk Config =="
sudo tee "$CONFIG_FILE" >/dev/null <<EOF
{
  "url": "$KIOSK_URL",
  "chromiumCommand": "$CHROMIUM_CMD"
}
EOF

echo "== WLAN konfigurieren =="
if [ -n "$WIFI_SSID" ]; then
  if [ -n "$WIFI_PASSWORD" ]; then
    sudo nmcli dev wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" || true
  else
    sudo nmcli dev wifi connect "$WIFI_SSID" || true
  fi

  if [ "$WIFI_HIDDEN" = "true" ]; then
    sudo nmcli connection modify "$WIFI_SSID" 802-11-wireless.hidden yes || true
  fi
else
  echo "ℹ️ Kein WLAN in kiosk-config.env definiert"
fi

echo "== kiosk.sh =="
sudo tee "$APP_DIR/kiosk.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/kiosk-display/config.json"

URL="$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['url'])")"
CHROMIUM_CMD="$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('chromiumCommand', 'chromium'))")"

export DISPLAY=:0

xset s off || true
xset -dpms || true
xset s noblank || true
unclutter -idle 0.5 &

exec "$CHROMIUM_CMD" \
  --noerrdialogs \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --kiosk "$URL"
EOF

echo "== Rechte =="
sudo chmod +x "$APP_DIR/kiosk.sh"
sudo chown -R "$USER_NAME:$USER_NAME" "$APP_DIR"

echo "== systemd Service =="
sudo tee /etc/systemd/system/kiosk-display.service >/dev/null <<EOF
[Unit]
Description=Kiosk Display
After=graphical.target network-online.target
Wants=network-online.target

[Service]
User=$USER_NAME
Environment=DISPLAY=:0
ExecStart=$APP_DIR/kiosk.sh
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

echo "== Enable Service =="
sudo systemctl daemon-reload
sudo systemctl enable kiosk-display
sudo systemctl restart kiosk-display

echo "== DONE =="
echo "👤 User: $USER_NAME"
echo "🏷️ Hostname: $KIOSK_HOSTNAME"
echo "🌐 URL: $KIOSK_URL"
echo "📡 IP:"
hostname -I
