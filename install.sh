#!/usr/bin/env bash
set -euo pipefail

REPO_BASE="https://raw.githubusercontent.com/willi84/kiosk-pi/main"

echo "⬇️ Lade Dateien..."

curl -fsSL "$REPO_BASE/setup-kiosk.sh" -o setup-kiosk.sh
curl -fsSL "$REPO_BASE/kiosk-config.env" -o kiosk-config.env

echo "🔧 Rechte setzen..."
chmod +x setup-kiosk.sh

echo "📝 Bitte config anpassen:"
echo "nano kiosk-config.env"

echo "🚀 Danach ausführen:"
echo "./setup-kiosk.sh"
