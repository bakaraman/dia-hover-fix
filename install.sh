#!/bin/bash
# Builds dia-hover-fix and installs it as a LaunchAgent for the current user.
set -euo pipefail
cd "$(dirname "$0")"

label="local.dia-hover-fix"
dest="$HOME/Library/Application Support/DiaHoverFix"
plist="$HOME/Library/LaunchAgents/$label.plist"

mkdir -p "$dest" "$HOME/Library/LaunchAgents"
swiftc -O -swift-version 5 -o "$dest/dia-hover-fix" dia-hover-fix.swift

cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$label</string>
	<key>ProgramArguments</key>
	<array>
		<string>$dest/dia-hover-fix</string>
		<string>$HOME/Library/Logs/dia-hover-fix.log</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>StandardErrorPath</key>
	<string>$HOME/Library/Logs/dia-hover-fix.err.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "Installed and running. Log: ~/Library/Logs/dia-hover-fix.log"
