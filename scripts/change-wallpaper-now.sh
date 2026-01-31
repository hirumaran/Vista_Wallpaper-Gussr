#!/bin/bash

# =============================================================================
# Change Wallpaper Now - Manual trigger for Bing Daily Wallpaper
# =============================================================================
# This script provides a manual way to change the wallpaper immediately.
# Run this anytime you want to get a new Bing wallpaper.
# 
# Usage:
#   ./change-wallpaper-now.sh         - Normal mode with smart filtering
#   ./change-wallpaper-now.sh --no-filter   - Disable filtering
# =============================================================================

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🖼️  Bing Wallpaper Changer"
echo "========================="
echo ""
echo "📡 Fetching today's wallpaper from Bing..."
echo ""

# Call the main wallpaper script to cycle/shuffle wallpaper
"$SCRIPT_DIR/set-bing-wallpaper.sh" --cycle "$@"

# Check the exit status
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Done! Your wallpaper has been updated."
    echo "   Check your desktop to see the new Bing Daily image."
else
    echo ""
    echo "❌ Failed to change wallpaper. Check the log for details:"
    echo "   ~/Library/Logs/bing-wallpaper.log"
fi
