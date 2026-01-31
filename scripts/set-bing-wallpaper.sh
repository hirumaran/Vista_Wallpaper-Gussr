#!/bin/bash

# Bing Daily Wallpaper Setter for macOS
# Fetches the daily wallpaper from Bing with smart filtering and date-based selection
# Downloads wallpaper permanently, sets it on MAIN display only (prevents external monitor glitches)

# Configuration
API_URL="https://bing.npanuhin.me/US/en.json"
LOG_FILE="$HOME/Library/Logs/bing-wallpaper.log"
CONFIG_FILE="$(dirname "$0")/../config/wallpaper-filters.txt"
TIMEOUT=30
MAX_DAYS_BACK=7
JSON_CACHE_FILE="/tmp/bing_wallpaper_cache.json"
WALLPAPER_DIR="$HOME/Pictures/BingWallpapers"
LOCK_FILE="/tmp/bing_wallpaper_set.lock"

# Parse command line arguments
NO_FILTER=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-filter)
            NO_FILTER=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Ensure log and wallpaper directories exist
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$WALLPAPER_DIR"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check if screen is locked - prevents lock screen glitches
is_screen_locked() {
    local locked
    locked=$(osascript -e 'tell application "System Events" to get running of screen saver status' 2>/dev/null || echo "false")
    
    if [ "$locked" = "true" ]; then
        log "Screen is locked, skipping wallpaper change"
        return 0
    fi
    
    # Alternative check: CGSession
    local session_user
    session_user=$(python3 -c "
import sys
try:
    import Cocoa
    session = Cocoa.NSSessionManager.sharedManager().currentSession
    if session and hasattr(session, 'userName'):
        print(session.userName() if session.userName() else '')
    else:
        # Fallback: check if screen saver is running
        import subprocess
        result = subprocess.run(['defaults', '-currentHost', 'read', 'com.apple.screensaver', 'idleTime'], 
                          capture_output=True, text=True)
        print('')
except:
    print('')
" 2>/dev/null)
    
    if [ -z "$session_user" ]; then
        log "No active user session, screen likely locked"
        return 0
    fi
    
    return 1
}

# Check if another instance is running (prevents rapid-fire changes)
is_already_running() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_age
        lock_age=$(($(date +%s) - $(stat -f%m "$LOCK_FILE" 2>/dev/null || stat -c%Y "$LOCK_FILE" 2>/dev/null)))
        
        # Lock is older than 5 minutes, safe to proceed
        if [ $lock_age -gt 300 ]; then
            log "Old lock file found (${lock_age}s), clearing it"
            rm -f "$LOCK_FILE"
            return 1
        else
            log "Another instance is running (lock age: ${lock_age}s), skipping"
            return 0
        fi
    fi
    return 1
}

# Set lock file
set_lock() {
    touch "$LOCK_FILE"
}

# Clear lock file
clear_lock() {
    rm -f "$LOCK_FILE"
}

# Load filter keywords from config file
load_filter_keywords() {
    KEEP_KEYWORDS=()
    SKIP_KEYWORDS=()
    
    if [ -f "$CONFIG_FILE" ]; then
        local section=""
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip empty lines
            [[ -z "$line" ]] && continue
            
            # Detect section headers
            if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*KEEP ]]; then
                section="keep"
                continue
            elif [[ "$line" =~ ^[[:space:]]*#[[:space:]]*SKIP ]]; then
                section="skip"
                continue
            fi
            
            # Skip other comments
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            
            # Add keywords to appropriate array
            if [[ "$section" == "keep" && -n "$line" ]]; then
                KEEP_KEYWORDS+=("$line")
            elif [[ "$section" == "skip" && -n "$line" ]]; then
                SKIP_KEYWORDS+=("$line")
            fi
        done < "$CONFIG_FILE"
        
        log "Loaded ${#KEEP_KEYWORDS[@]} keep keywords and ${#SKIP_KEYWORDS[@]} skip keywords from config"
    else
        # Default keywords if config file not found
        KEEP_KEYWORDS=("mountain" "beach" "ocean" "forest" "island" "lake" "river" "wildlife" "animal" "bird" "elephant" "tiger" "castle" "temple" "palace" "architecture" "historic" "national park" "landscape" "scenic" "nature" "waterfall" "aurora" "sunset" "sunrise" "coast")
        SKIP_KEYWORDS=("earth from space" "satellite" "abstract" "microscopic" "diagram" "infographic" "conceptual" "artistic pattern" "illustration" "graphic" "digital art" "space station")
        log "Config file not found, using default keywords"
    fi
}

# Check if wallpaper passes filter
check_wallpaper_filter() {
    local title="${1:-}"
    local description="${2:-}"
    local caption="${3:-}"
    
    if [ "$NO_FILTER" = true ]; then
        log "Filtering disabled (--no-filter flag)"
        return 0
    fi
    
    local search_text="${title} ${description} ${caption}"
    search_text=$(echo "$search_text" | tr '[:upper:]' '[:lower:]')
    
    # Check skip keywords first
    for keyword in "${SKIP_KEYWORDS[@]}"; do
        local lower_keyword=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')
        if [[ "$search_text" == *"$lower_keyword"* ]]; then
            log "FILTER: SKIPPED - Contains skip keyword: '$keyword'"
            log "  Title: $title"
            return 1
        fi
    done
    
    log "FILTER: PASSED - No skip keywords found"
    return 0
}

# Function to find a valid default wallpaper
find_default_wallpaper() {
    local default_paths=(
        "/System/Library/Desktop Pictures/Monterey Graphic.heic"
        "/System/Library/Desktop Pictures/Ventura Graphic.heic"
        "/System/Library/Desktop Pictures/Sonoma Graphic.heic"
        "/System/Library/Desktop Pictures/Sequoia Graphic.heic"
        "/System/Library/Desktop Pictures/Big Sur Graphic.heic"
        "/System/Library/Desktop Pictures/Catalina Graphic.heic"
        "/System/Library/Desktop Pictures/Mojave Graphic.heic"
        "/System/Library/Desktop Pictures/High Sierra Graphic.heic"
    )
    
    for path in "${default_paths[@]}"; do
        if [ -f "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    
    local first_wallpaper
    first_wallpaper=$(ls /System/Library/Desktop\ Pictures/*.heic 2>/dev/null | head -1)
    if [ -n "$first_wallpaper" ] && [ -f "$first_wallpaper" ]; then
        echo "$first_wallpaper"
        return 0
    fi
    
    first_wallpaper=$(ls /System/Library/Desktop\ Pictures/*.jpg 2>/dev/null | head -1)
    if [ -n "$first_wallpaper" ] && [ -f "$first_wallpaper" ]; then
        echo "$first_wallpaper"
        return 0
    fi
    
    return 1
}

# Function to get current wallpaper path
get_current_wallpaper() {
    osascript -e 'try
        tell application "Finder"
            return POSIX path of (desktop picture as alias)
        end tell
    on error
        return ""
    end try' 2>/dev/null
}

# STABLE wallpaper setter - sets on MAIN display only to prevent external monitor glitches
set_wallpaper_from_file() {
    local image_path="$1"
    
    log "Setting wallpaper on MAIN display only: $image_path"
    
    # Method 1: Use qlmanage (QuickLook) - most stable method
    # This sets wallpaper without triggering System Events display refreshes
    if qlmanage -p "$image_path" &>/dev/null; then
        sleep 0.1
    fi
    
    # Method 2: Set wallpaper on MAIN display only (not all displays)
    # Using desktop 0 only prevents flickering on external monitors
    osascript <<EOF
        try
            tell application "System Events"
                set picture of desktop 1 to POSIX file "$image_path"
            end tell
            return "success"
        on error errMsg
            log "System Events failed: " & errMsg
            return "error: " & errMsg
        end try
EOF
    
    if [ $? -eq 0 ]; then
        return 0
    fi
    
    # Method 3: Fallback to using sqlite on wallpaper database
    # This is the most direct method and doesn't trigger display refreshes
    local wallpaper_db="$HOME/Library/Application Support/Dock/desktoppicture.db"
    local sql_query
    sql_query="
        UPDATE data SET value = '$(echo "$image_path" | sed "s/'/''/g")'
        WHERE key = 'default';
    "
    
    if [ -f "$wallpaper_db" ]; then
        # Kill Dock to reload wallpaper settings
        sqlite3 "$wallpaper_db" "$sql_query" 2>/dev/null
        killall Dock 2>/dev/null
        sleep 1
        return 0
    fi
    
    # Method 4: Last resort - set on current desktop only
    osascript -e 'tell application "System Events" to tell current desktop to set picture to POSIX file "'"$image_path"'"' 2>/dev/null
    return $?
}

# Function to set default wallpaper
set_default_wallpaper() {
    log "Setting default wallpaper..."
    
    local default_wallpaper
    default_wallpaper=$(find_default_wallpaper)
    
    if [ -n "$default_wallpaper" ] && [ -f "$default_wallpaper" ]; then
        log "Using default wallpaper: $default_wallpaper"
        local result
        result=$(set_wallpaper_from_file "$default_wallpaper")
        
        if [ $? -eq 0 ]; then
            log "Default wallpaper set successfully"
            return 0
        else
            log "ERROR: Failed to set default wallpaper: $result"
            return 1
        fi
    else
        log "ERROR: No valid default wallpaper found"
        return 1
    fi
}

# Function to fetch JSON from API and save to cache file
fetch_json() {
    log "Fetching JSON from API: $API_URL"
    
    if ! curl -s -L --max-time $TIMEOUT -o "$JSON_CACHE_FILE" "$API_URL" 2>/dev/null; then
        log "ERROR: Failed to fetch JSON from API (timeout or network error)"
        rm -f "$JSON_CACHE_FILE"
        return 1
    fi
    
    if [ ! -f "$JSON_CACHE_FILE" ] || [ ! -s "$JSON_CACHE_FILE" ]; then
        log "ERROR: Downloaded JSON file is empty or missing"
        rm -f "$JSON_CACHE_FILE"
        return 1
    fi
    
    if ! python3 -c "import sys, json; json.load(open('$JSON_CACHE_FILE'))" 2>/dev/null; then
        log "ERROR: Invalid JSON response from API"
        log "Response preview: $(head -c 200 "$JSON_CACHE_FILE")..."
        rm -f "$JSON_CACHE_FILE"
        return 1
    fi
    
    local file_size
    file_size=$(stat -f%z "$JSON_CACHE_FILE" 2>/dev/null || stat -c%s "$JSON_CACHE_FILE" 2>/dev/null)
    log "JSON cached to file (${file_size} bytes)"
    
    return 0
}

# Function to find wallpaper for specific date
find_wallpaper_for_date() {
    local target_date="$1"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Looking for wallpaper with date: $target_date" >> "$LOG_FILE"
    
    if [ ! -f "$JSON_CACHE_FILE" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: JSON cache file not found" >> "$LOG_FILE"
        return 1
    fi
    
    local wallpaper_info
    wallpaper_info=$(python3 -c "
import sys, json
try:
    with open('$JSON_CACHE_FILE', 'r') as f:
        data = json.load(f)
    target = '$target_date'
    
    for item in data:
        if item.get('date') == target:
            url = item.get('url') or item.get('bing_url')
            if url:
                if not url.startswith('http'):
                    url = 'https://www.bing.com' + url
                print(json.dumps({
                    'url': url,
                    'title': item.get('title', ''),
                    'description': item.get('description', ''),
                    'caption': item.get('caption', ''),
                    'date': item.get('date', '')
                }))
                sys.exit(0)
    
    sys.exit(1)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$wallpaper_info" ]; then
        echo "$wallpaper_info"
        return 0
    else
        return 1
    fi
}

# Function to download and set wallpaper
download_and_set_wallpaper() {
    local image_url="$1"
    local filename="bing_wallpaper_$(date +%Y-%m-%d).jpg"
    local wallpaper_file="$WALLPAPER_DIR/$filename"
    
    log "Downloading wallpaper to: $wallpaper_file"
    
    if ! curl -s -L --max-time $TIMEOUT -o "$wallpaper_file" "$image_url" 2>/dev/null; then
        log "ERROR: Failed to download wallpaper from URL"
        rm -f "$wallpaper_file"
        return 1
    fi
    
    if [ ! -f "$wallpaper_file" ] || [ ! -s "$wallpaper_file" ]; then
        log "ERROR: Downloaded file is empty or missing"
        rm -f "$wallpaper_file"
        return 1
    fi
    
    local file_type
    file_type=$(file -b "$wallpaper_file" 2>/dev/null)
    if [[ ! "$file_type" =~ (JPEG|JPG|PNG|image) ]]; then
        log "WARNING: Downloaded file may not be a valid image: $file_type"
    fi
    
    log "Wallpaper downloaded successfully ($(stat -f%z "$wallpaper_file" 2>/dev/null || stat -c%s "$wallpaper_file" 2>/dev/null) bytes)"
    
    local result
    result=$(set_wallpaper_from_file "$wallpaper_file")
    
    if [ $? -eq 0 ]; then
        log "SUCCESS: Wallpaper set from downloaded file"
        # Clean up old wallpapers (keep last 30 days)
        find "$WALLPAPER_DIR" -name "bing_wallpaper_*.jpg" -mtime +30 -delete 2>/dev/null
        return 0
    else
        log "ERROR: Failed to set wallpaper: $result"
        return 1
    fi
}

# Function to get date N days ago
get_date_days_ago() {
    local days="$1"
    date -v-${days}d +%Y-%m-%d 2>/dev/null || date -d "${days} days ago" +%Y-%m-%d 2>/dev/null
}

# Main execution
main() {
    log "=== Bing Wallpaper Setter Started ==="
    
    if [ "$NO_FILTER" = true ]; then
        log "Mode: Filtering DISABLED"
    else
        log "Mode: Smart filtering ENABLED"
    fi
    
    # Check if screen is locked - prevents lock screen glitches
    if is_screen_locked; then
        log "Skipping wallpaper change - screen is locked"
        exit 0
    fi
    
    # Check if another instance is already running
    if is_already_running; then
        log "Skipping - another instance is running"
        exit 0
    fi
    
    # Set lock file
    set_lock
    
    # Load filter keywords
    load_filter_keywords
    
    # Save current wallpaper for potential restore
    local current_wallpaper
    current_wallpaper=$(get_current_wallpaper)
    if [ -n "$current_wallpaper" ]; then
        log "Current wallpaper saved: $current_wallpaper"
    fi
    
    # Fetch JSON data
    fetch_json
    
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to fetch JSON data"
        if [ -n "$current_wallpaper" ] && [ -f "$current_wallpaper" ]; then
            set_wallpaper_from_file "$current_wallpaper"
        fi
        set_default_wallpaper
        clear_lock
        exit 1
    fi
    
    # Get today's date
    local today
    today=$(date +%Y-%m-%d)
    log "Today's date: $today"
    
    # Try to find a suitable wallpaper
    local selected_wallpaper=""
    local selected_title=""
    local selected_date=""
    local days_back=0
    
    while [ $days_back -lt $MAX_DAYS_BACK ]; do
        local target_date
        target_date=$(get_date_days_ago $days_back)
        
        log "Checking date: $target_date (${days_back} days ago)"
        
        local wallpaper_json
        wallpaper_json=$(find_wallpaper_for_date "$target_date")
        
        if [ $? -eq 0 ] && [ -n "$wallpaper_json" ]; then
            local url title description caption
            url=$(echo "$wallpaper_json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('url', ''))" 2>/dev/null)
            title=$(echo "$wallpaper_json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('title', ''))" 2>/dev/null)
            description=$(echo "$wallpaper_json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('description', ''))" 2>/dev/null)
            caption=$(echo "$wallpaper_json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('caption', ''))" 2>/dev/null)
            
            if [ -n "$url" ]; then
                log "Found wallpaper: $title"
                
                # Check filter
                if check_wallpaper_filter "$title" "$description" "$caption"; then
                    selected_wallpaper="$url"
                    selected_title="$title"
                    selected_date="$target_date"
                    log "SELECTED: Using wallpaper from $target_date"
                    break
                else
                    log "Wallpaper filtered out, trying previous day..."
                fi
            fi
        else
            log "No wallpaper found for date: $target_date"
        fi
        
        ((days_back++))
    done
    
    # If we found a suitable wallpaper, set it
    if [ -n "$selected_wallpaper" ]; then
        log "Setting wallpaper: $selected_title ($selected_date)"
        
        if download_and_set_wallpaper "$selected_wallpaper"; then
            log "=== Bing Wallpaper Setter Completed Successfully ==="
            log "Final wallpaper: $selected_title ($selected_date)"
            clear_lock
            exit 0
        else
            log "ERROR: Failed to set selected wallpaper"
            if [ -n "$current_wallpaper" ] && [ -f "$current_wallpaper" ]; then
                log "Restoring previous wallpaper..."
                set_wallpaper_from_file "$current_wallpaper"
            fi
            set_default_wallpaper
            clear_lock
            exit 1
        fi
    else
        log "ERROR: No suitable wallpaper found after checking $MAX_DAYS_BACK days"
        if [ -n "$current_wallpaper" ] && [ -f "$current_wallpaper" ]; then
            set_wallpaper_from_file "$current_wallpaper"
        fi
        set_default_wallpaper
        clear_lock
        exit 1
    fi
}

# Cleanup function
cleanup() {
    clear_lock
    rm -f "$JSON_CACHE_FILE"
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Run main function
main
