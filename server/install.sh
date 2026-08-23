#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo "Usage: bash install.sh /path/to/cstrike" >&2; exit 2; }
GAME_DIR="$1"
BASE_URL="https://raw.githubusercontent.com/DmitriySivko/oldfrag-anticheat/main"
META="$GAME_DIR/addons/metamod/plugins.ini"
AMXX="$GAME_DIR/addons/amxmodx/configs/plugins.ini"
PLUGIN_DIR="$GAME_DIR/addons/amxmodx/plugins"
CONFIG_DIR="$GAME_DIR/addons/amxmodx/configs"
STAMP="$(date +%Y%m%d_%H%M%S)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for p in "$META" "$AMXX" "$PLUGIN_DIR" "$CONFIG_DIR" "$GAME_DIR/addons/rechecker"; do
  [[ -e "$p" ]] || { echo "Missing: $p" >&2; exit 1; }
done

curl -fsSL "$BASE_URL/dist/oldfrag_anticheat.amxx" -o "$TMP/oldfrag_anticheat.amxx"
curl -fsSL "$BASE_URL/dist/oldfrag_anticheat.amxx.sha256" -o "$TMP/oldfrag_anticheat.amxx.sha256"
(cd "$TMP" && sha256sum -c oldfrag_anticheat.amxx.sha256)
curl -fsSL "$BASE_URL/server/oldfrag_anticheat.cfg" -o "$TMP/oldfrag_anticheat.cfg"

cp -a "$META" "$META.oldfrag.$STAMP.bak"
cp -a "$AMXX" "$AMXX.oldfrag.$STAMP.bak"
[[ ! -e "$CONFIG_DIR/oldfrag_anticheat.cfg" ]] || cp -a "$CONFIG_DIR/oldfrag_anticheat.cfg" "$CONFIG_DIR/oldfrag_anticheat.cfg.$STAMP.bak"
[[ ! -e "$PLUGIN_DIR/oldfrag_anticheat.amxx" ]] || cp -a "$PLUGIN_DIR/oldfrag_anticheat.amxx" "$PLUGIN_DIR/oldfrag_anticheat.amxx.$STAMP.bak"

awk '/addons\/rechecker\/rechecker_mm_i386\.so/ { rc=$0; next } /addons\/amxmodx\/dlls\/amxmodx_mm_i386\.so/ { if (rc) { print rc; rc="" }; print; next } { print } END { if (rc) print rc }' "$META" > "$TMP/metamod.plugins.ini"
awk '/^[[:space:]]*rc_basechanger\.amxx/ { print ";" $0 " ; disabled by OldFragAC"; next } /^[[:space:]]*oldfrag_anticheat\.amxx/ { next } { print } /^[[:space:]]*fresh_bans\.amxx/ { print "oldfrag_anticheat.amxx" }' "$AMXX" > "$TMP/amxx.plugins.ini"

install -m 0644 "$TMP/oldfrag_anticheat.amxx" "$PLUGIN_DIR/oldfrag_anticheat.amxx"
install -m 0644 "$TMP/oldfrag_anticheat.cfg" "$CONFIG_DIR/oldfrag_anticheat.cfg"
install -m 0644 "$TMP/metamod.plugins.ini" "$META"
install -m 0644 "$TMP/amxx.plugins.ini" "$AMXX"

echo "Installed. Backups: .oldfrag.$STAMP.bak"
echo "Restart server and run: ofac_status"
