#!/bin/bash
# Stops dia-hover-fix and removes it. The log stays in ~/Library/Logs.
set -uo pipefail

label="local.dia-hover-fix"
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$label.plist"
rm -rf "$HOME/Library/Application Support/DiaHoverFix"
echo "Removed."
