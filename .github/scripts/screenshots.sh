#!/usr/bin/env bash
# Boot an iPhone simulator, install the built app, launch it once per line of
# .github/screenshots.txt and save a PNG of each. Usage: screenshots.sh <path/to/Days.app> <outdir>
set -euo pipefail
APP="$1"; OUT="$2"
BID=com.viraajrandhawa.182days
mkdir -p "$OUT"
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devs = json.load(sys.stdin)["devices"]
phones = [(rt, d) for rt, ds in devs.items() if "iOS" in rt for d in ds if d["name"].startswith("iPhone")]
phones.sort(key=lambda t: t[0], reverse=True)
pick = [d for rt, d in phones if d["name"] == "iPhone 17 Pro"] or [d for rt, d in phones if "Pro" in d["name"] and "Max" not in d["name"]] or [d for rt, d in phones]
print(pick[0]["udid"])')
echo "simulator $UDID"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiBars 3 --cellularBars 4 --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$UDID" "$APP"
grep -vE '^\s*(#|$)' .github/screenshots.txt | while read -r name args; do
  xcrun simctl terminate "$UDID" "$BID" </dev/null >/dev/null 2>&1 || true
  # shellcheck disable=SC2086
  xcrun simctl launch "$UDID" "$BID" $args </dev/null
  sleep 6
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" </dev/null
  echo "shot $name"
done
