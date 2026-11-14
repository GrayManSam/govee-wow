#!/usr/bin/env bash
# Installs govee-wow for the current user: scripts, the CouchLights addon, the systemd service.
set -euo pipefail
cd "$(dirname "$0")"
WOW_DIR="${WOW_DIR:-$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_}"

install -Dm755 bin/govee-wow "$HOME/.local/bin/govee-wow"
install -Dm755 bin/govee-wow-test "$HOME/.local/bin/govee-wow-test"

if [[ -d "$WOW_DIR/Interface/AddOns" ]]; then
  cp -r addon/CouchLights "$WOW_DIR/Interface/AddOns/"
  echo "CouchLights addon -> $WOW_DIR/Interface/AddOns"
else
  echo "WoW AddOns folder not found at: $WOW_DIR/Interface/AddOns"
  echo "  copy addon/CouchLights there yourself, or rerun with WOW_DIR=/path/to/_forever_"
fi

mkdir -p "$HOME/.config/systemd/user"
sed "s|^ExecStart=.*|ExecStart=%h/.local/bin/govee-wow daemon|" systemd/govee-wow.service \
  > "$HOME/.config/systemd/user/govee-wow.service"
if [[ "$WOW_DIR" != "$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_" ]]; then
  mkdir -p "$HOME/.config/systemd/user/govee-wow.service.d"
  printf '[Service]\nEnvironment="WOW_DIR=%s"\n' "$WOW_DIR" \
    > "$HOME/.config/systemd/user/govee-wow.service.d/wow-dir.conf"
fi
systemctl --user daemon-reload
systemctl --user enable --now govee-wow.service
echo "Installed. Turn on LAN Control for each light in the Govee Home app, then: govee-wow demo 30"
