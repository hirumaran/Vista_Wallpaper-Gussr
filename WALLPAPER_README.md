# Bing Wallpaper Auto-Setter for macOS

A lightweight wallpaper rotation system that automatically sets your Mac's desktop background to Bing's daily image. Downloads wallpaper temporarily to `/tmp`, sets it, then cleans up - no permanent storage needed.

## Features

- **🎯 Smart Filtering**: Automatically filters out boring wallpapers (space images, abstracts, etc.)
- **📅 Date-Based Selection**: Always gets the most recent wallpaper for today's date
- **🔄 Intelligent Fallback**: Goes back up to 7 days to find a beautiful wallpaper
- **⚙️ Configurable Filters**: Customize which wallpapers to keep/skip via config file
- **🚫 Filter Bypass**: Use `--no-filter` flag to disable filtering when desired
- **⏰ Automatic Updates**: Runs daily at 8:00 AM via launchd
- **🛡️ Smart Fallback**: Reverts to macOS default wallpaper if internet/Bing fails
- **📝 Error Logging**: Detailed logs for troubleshooting
- **🔒 Non-intrusive**: Doesn't interfere with your existing Vista game
- **🧹 Auto-cleanup**: Temp files deleted immediately after setting wallpaper

## Quick Start

### Installation

```bash
# From the project root:
./scripts/install-wallpaper.sh
```

This will:
1. Set up a launchd agent to run daily at 8:00 AM
2. Set the wallpaper immediately (test run)
3. Enable automatic startup

### Manual Usage

```bash
# Set wallpaper right now (Trigger immediately):
./scripts/change-wallpaper-now.sh

# Force change even if keyword filter rejects it:
./scripts/change-wallpaper-now.sh --no-filter
```

### ⌨️ Add Keyboard Shortcut (Optional)

You can trigger a wallpaper change with a keyboard shortcut!

1. Open **Automator** on your Mac
2. Create a new **Quick Action**
3. Set "Workflow receives" to **no input** in **any application**
4. Add action: **Run Shell Script**
5. Paste the full path to your script:
   ```bash
   /Users/thirumarandeepak/Documents/bg_spot/scripts/change-wallpaper-now.sh
   ```
6. Save as "Change Bing Wallpaper"
7. Go to **System Settings** → **Keyboard** → **Keyboard Shortcuts** → **Services**
8. Find "Change Bing Wallpaper" and assign a shortcut (e.g., `Cmd+Option+W`)

### Uninstallation

```bash
./scripts/uninstall-wallpaper.sh
```

## How It Works

### Smart Filtering Workflow

1. **📡 Fetches**: Calls `https://bing.npanuhin.me/US/en.json` for wallpapers
2. **📅 Finds Today's**: Looks for wallpaper matching today's date (YYYY-MM-DD)
3. **🔍 Filters**: Checks title/description against skip/keep keywords
4. **✅ If Good**: Downloads and sets the wallpaper
5. **❌ If Bad**: Tries previous day's wallpaper (up to 7 days back)
6. **💾 Downloads**: Saves the image temporarily to `/tmp/bing_wallpaper_[timestamp].jpg`
7. **🖼️ Sets**: Uses AppleScript to set the wallpaper from the local file
8. **🗑️ Cleans Up**: Deletes the temp file immediately after setting
9. **🛡️ Falls Back**: On any error, reverts to macOS default wallpaper (auto-detected)

### What Gets Filtered Out?

**Automatically Skipped:**
- Earth from space / satellite images
- Abstract art and patterns
- Microscopic images
- Diagrams and infographics
- Dark/minimalist backgrounds

**Preferred:**
- Natural landscapes (mountains, beaches, forests)
- Wildlife and animals
- Historic architecture
- Scenic locations
- Natural phenomena (auroras, waterfalls, sunsets)

## File Structure

```
bg_spot/
├── scripts/
│   ├── set-bing-wallpaper.sh      # Main wallpaper setter (runs daily)
│   ├── change-wallpaper-now.sh    # Manual trigger script (Run this one!)
│   ├── install-wallpaper.sh       # One-time setup
│   ├── uninstall-wallpaper.sh     # Cleanup script
│   └── test-wallpaper.sh          # Component testing
├── launchd/
│   └── com.user.bingwallpaper.plist  # macOS scheduler config
├── config/
│   └── wallpaper-filters.txt      # Customizable filter keywords
├── WALLPAPER_README.md            # This file
├── FILTERING.md                   # Detailed filtering documentation
├── INTEGRATION.md                 # Architecture overview
└── index.html                     # Your existing Vista game (unchanged)
```

## Logs & Debugging

Log files are stored in `~/Library/Logs/`:
- `bing-wallpaper.log` - Main script activity
- `bing-wallpaper-launchd.log` - launchd stdout
- `bing-wallpaper-launchd-error.log` - launchd stderr

View logs:
```bash
tail -f ~/Library/Logs/bing-wallpaper.log
```

## Checking Status

```bash
# Check if agent is loaded
launchctl list | grep bingwallpaper

# View detailed info
launchctl print gui/$(id -u)/com.user.bingwallpaper
```

## Technical Details

### Why Direct URLs?
- **Pros**: Zero storage, zero bandwidth for you, always current, instant updates
- **Cons**: Requires internet connection, dependent on Bing's URL stability

### Fallback Strategy
When the script fails (no internet, API down, invalid JSON):
1. Logs the error
2. Sets wallpaper to `/System/Library/Desktop Pictures/Monterey Graphic.heic`
3. Continues running on next scheduled time

### Scheduling
Uses macOS `launchd` (preferred over cron on macOS):
- Runs at 8:00 AM daily
- Also runs on system boot (RunAtLoad)
- Survives restarts
- No user interaction needed

## Integration with Vista Game

This wallpaper system is **completely separate** from your existing Vista game:
- The game (`index.html`) continues to work normally
- Both use the same Bing API but independently
- No code changes needed to the game
- Can use game and have auto-wallpaper simultaneously

## Requirements

- macOS (tested on Monterey and later)
- Internet connection (for fetching new wallpapers)
- Bash shell
- Python3 (for JSON parsing - pre-installed on macOS)
- curl (pre-installed on macOS)

## Smart Filtering Configuration

### Customizing Filter Keywords

Edit `config/wallpaper-filters.txt` to customize which wallpapers are kept or skipped:

```bash
nano config/wallpaper-filters.txt
```

**Keep Keywords** - Wallpapers with these are preferred:
- Nature: mountain, beach, forest, lake, waterfall
- Wildlife: animal, bird, tiger, elephant, whale
- Architecture: castle, temple, palace, historic
- Scenic: national park, landscape, aurora, sunset

**Skip Keywords** - Wallpapers with these are rejected:
- Space: earth from space, satellite, space station
- Abstract: abstract art, geometric, fractal
- Technical: microscopic, diagram, infographic

### Disabling Filters

To get ALL wallpapers without filtering:

```bash
./scripts/change-wallpaper-now.sh --no-filter
```

### Viewing Filter Logs

See which wallpapers were filtered and why:

```bash
# View all filtering decisions
grep "FILTER" ~/Library/Logs/bing-wallpaper.log

# See which wallpaper was selected
grep "SELECTED" ~/Library/Logs/bing-wallpaper.log
```

**Example log output:**
```
[2026-01-30 08:00:02] FILTER: SKIPPED - Contains skip keyword: 'space station'
[2026-01-30 08:00:03] FILTER: PASSED - No skip keywords found
[2026-01-30 08:00:03] SELECTED: Using wallpaper from 2026-01-29
```

### Date-Based Fallback

If today's wallpaper is filtered out, the script automatically tries:
- Yesterday's wallpaper
- Day before yesterday
- Up to 7 days back
- Uses the first beautiful wallpaper it finds

## Troubleshooting

### Wallpaper not changing?
1. Check internet connection
2. View logs: `cat ~/Library/Logs/bing-wallpaper.log`
3. Try manual run: `./scripts/change-wallpaper-now.sh`

### Getting too many "skipped" wallpapers?
- Check which keywords are triggering skips: `grep "SKIPPED" ~/Library/Logs/bing-wallpaper.log`
- Edit `config/wallpaper-filters.txt` to remove overly broad keywords
- Or use `--no-filter` to disable filtering temporarily

### Want to see what the script is doing?
Run with verbose output:
```bash
./scripts/change-wallpaper-now.sh 2>&1 | tee /dev/tty
```

### "Permission denied" when running scripts?
Run: `chmod +x scripts/*.sh`

### Want to change the schedule time?
Edit `launchd/com.user.bingwallpaper.plist`:
```xml
<key>StartCalendarInterval</key>
<dict>
    <key>Hour</key>
    <integer>YOUR_HOUR</integer>
    <key>Minute</key>
    <integer>YOUR_MINUTE</integer>
</dict>
```
Then reload: `launchctl unload ~/Library/LaunchAgents/com.user.bingwallpaper.plist && launchctl load ~/Library/LaunchAgents/com.user.bingwallpaper.plist`

## API Reference

The script uses the same API as your Vista game:
- **Endpoint**: `https://bing.npanuhin.me/US/en.json`
- **Response**: JSON array of wallpaper objects
- **URL Field**: Uses `url` or `bing_url` from the first (most recent) item

## License

Part of the Vista project. Use freely.
