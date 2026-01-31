#!/bin/bash

# Uninstall script for Bing Wallpaper Setter
# Removes the launchd agent and cleans up

LAUNCHD_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.user.bingwallpaper.plist"
PLIST_PATH="$LAUNCHD_DIR/$PLIST_NAME"

echo "🗑️  Bing Wallpaper Setter - Uninstallation"
echo "============================================"
echo ""

# Unload the agent if it's loaded
if [ -f "$PLIST_PATH" ]; then
    echo "🛑 Stopping and unloading launchd agent..."
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    launchctl remove com.user.bingwallpaper 2>/dev/null || true
    
    # Remove the plist file
    echo "🗑️  Removing plist file..."
    rm "$PLIST_PATH"
    echo "✅ Plist removed"
else
    echo "⚠️  Launchd agent not found (already uninstalled?)"
fi

echo ""
echo "🧹 Cleaning up log files..."
rm -f "$HOME/Library/Logs/bing-wallpaper.log"
rm -f "$HOME/Library/Logs/bing-wallpaper-launchd.log"
rm -f "$HOME/Library/Logs/bing-wallpaper-launchd-error.log"
rm -f "$HOME/.bing-wallpaper-state"
echo "✅ Log files removed"

echo ""
echo "✅ Uninstallation complete!"
echo ""
echo "Note: Your current wallpaper has not been changed."
echo "To restore a default wallpaper, go to System Settings > Wallpaper."
