#!/bin/bash

# Install script for Bing Wallpaper Setter
# Sets up the launchd agent to run automatically

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LAUNCHD_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.user.bingwallpaper.plist"
PLIST_SOURCE="$PROJECT_DIR/launchd/$PLIST_NAME"
PLIST_DEST="$LAUNCHD_DIR/$PLIST_NAME"

echo "🖼️  Bing Wallpaper Setter - Installation"
echo "=========================================="
echo ""

# Check if plist file exists
if [ ! -f "$PLIST_SOURCE" ]; then
    echo "❌ Error: Launchd plist not found at $PLIST_SOURCE"
    exit 1
fi

# Update plist with actual user path
if [ -f "$PLIST_SOURCE" ]; then
    echo "📋 Customizing plist for current user..."
    sed -i '' "s|/Users/thirumarandeepak|$HOME|g" "$PLIST_SOURCE"
fi

# Create LaunchAgents directory if it doesn't exist
echo "📁 Creating LaunchAgents directory..."
mkdir -p "$LAUNCHD_DIR"

# Copy plist to LaunchAgents
echo "📋 Installing launchd agent..."
cp "$PLIST_SOURCE" "$PLIST_DEST"

# Load the agent
echo "🚀 Loading launchd agent..."
launchctl load "$PLIST_DEST" 2>/dev/null || launchctl bootstrap gui/$(id -u) "$PLIST_DEST"

# Test run
echo "🧪 Running initial test..."
"$PROJECT_DIR/scripts/set-bing-wallpaper.sh"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Installation successful!"
    echo ""
    echo "📅 Schedule: Daily at 8:00 AM"
    echo "📍 Log file: $HOME/Library/Logs/bing-wallpaper.log"
    echo "🔧 To check status: launchctl list | grep bingwallpaper"
    echo "🗑️  To uninstall: ./scripts/uninstall-wallpaper.sh"
    echo ""
    echo "Your wallpaper will now update automatically with Bing's daily image!"
else
    echo ""
    echo "⚠️  Installation completed but initial test failed."
    echo "Check logs at: $HOME/Library/Logs/bing-wallpaper.log"
fi
