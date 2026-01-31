#!/bin/bash

# Bing Daily Wallpaper Setter for macOS
# ULTRA-STABLE version - prevents external monitor black screens permanently
# Key fix: Updates ALL display entries in wallpaper database, not just main display

# Configuration
API_URL="https://bing.npanuhin.me/US/en.json"
LOG_FILE="$HOME/Library/Logs/bing-wallpaper.log"
CONFIG_FILE="$(dirname "$0")/../config/wallpaper-filters.txt"
TIMEOUT=30
MAX_DAYS_BACK=7
JSON_CACHE_FILE="/tmp/bing_wallpaper_cache.json"
WALLPAPER_DIR="$HOME/Pictures/BingWallpapers"
STABLE_WALLPAPER_DIR="$HOME/Pictures/BingWallpapers/Stable"
LOCK_FILE="/tmp/bing_wallpaper_set.lock"
MAX_RETRIES=3
RETRY_DELAY=2

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

# Ensure directories exist
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$WALLPAPER_DIR"
mkdir -p "$STABLE_WALLPAPER_DIR"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check if screen is locked
is_screen_locked() {
    local locked
    locked=$(osascript -e 'tell application "System Events" to get running of screen saver status' 2>/dev/null || echo "false")
    
    if [ "$locked" = "true" ]; then
        log "Screen is locked, skipping wallpaper change"
        return 0
    fi
    
    local session_user
    session_user=$(python3 -c "
import sys
try:
    import Cocoa
    session = Cocoa.NSSessionManager.sharedManager().currentSession
    if session and hasattr(session, 'userName'):
        print(session.userName() if session.userName() else '')
    else:
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

# Check if another instance is running
is_already_running() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_age
        lock_age=$(($(date +%s) - $(stat -f%m "$LOCK_FILE" 2>/dev/null || stat -c%Y "$LOCK_FILE" 2>/dev/null)))
        
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

set_lock() { touch "$LOCK_FILE"; }
clear_lock() { rm -f "$LOCK_FILE"; }

# Load filter keywords
load_filter_keywords() {
    KEEP_KEYWORDS=()
    SKIP_KEYWORDS=()
    
    if [ -f "$CONFIG_FILE" ]; then
        local section=""
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" ]] && continue
            if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*KEEP ]]; then
                section="keep"
                continue
            elif [[ "$line" =~ ^[[:space:]]*#[[:space:]]*SKIP ]]; then
                section="skip"
                continue
            fi
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            
            if [[ "$section" == "keep" && -n "$line" ]]; then
                KEEP_KEYWORDS+=("$line")
            elif [[ "$section" == "skip" && -n "$line" ]]; then
                SKIP_KEYWORDS+=("$line")
            fi
        done < "$CONFIG_FILE"
        
        log "Loaded ${#KEEP_KEYWORDS[@]} keep keywords and ${#SKIP_KEYWORDS[@]} skip keywords from config"
    else
        KEEP_KEYWORDS=("mountain" "beach" "ocean" "forest" "island" "lake" "river" "wildlife" "animal" "bird" "elephant" "tiger" "castle" "temple" "palace" "architecture" "historic" "national park" "landscape" "scenic" "nature" "waterfall" "aurora" "sunset" "sunrise" "coast")
        SKIP_KEYWORDS=("earth from space" "satellite" "abstract" "microscopic" "diagram" "infographic" "conceptual" "artistic pattern" "illustration" "graphic" "digital art" "space station")
        log "Config file not found, using default keywords"
    fi
}

# Check wallpaper filter
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

# Find default wallpaper
find_default_wallpaper() {
    local default_paths=(
        "/System/Library/Desktop Pictures/Monterey Graphic.heic"
        "/System/Library/Desktop Pictures/Ventura Graphic.heic"
        "/System/Library/Desktop Pictures/Sonoma Graphic.heic"
        "/System/Library/Desktop Pictures/Sequoia Graphic.heic"
        "/System/Library/Desktop Pictures/Big Sur Graphic.heic"
        "/System/Library/Desktop Pictures/Catalina Graphic.heic"
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
    
    return 1
}

# BULLETPROOF wallpaper setter - updates ALL displays and verifies success
set_wallpaper_stable() {
    local image_path="$1"
    local attempt=0
    
    log "Setting wallpaper (STABLE method): $image_path"
    
    # Verify file exists and is readable
    if [ ! -f "$image_path" ] || [ ! -r "$image_path" ]; then
        log "ERROR: Wallpaper file not accessible: $image_path"
        return 1
    fi
    
    # Copy to stable location (external monitors need this)
    local stable_filename="current_wallpaper.jpg"
    local stable_path="$STABLE_WALLPAPER_DIR/$stable_filename"
    
    log "Creating stable copy for external monitors: $stable_path"
    cp "$image_path" "$stable_path"
    chmod 644 "$stable_path"
    sync  # Force write to disk
    
    # Verify stable copy
    if [ ! -f "$stable_path" ] || [ ! -s "$stable_path" ]; then
        log "ERROR: Failed to create stable copy"
        return 1
    fi
    
    # Use the stable path for all operations
    image_path="$stable_path"
    
    while [ $attempt -lt $MAX_RETRIES ]; do
        ((attempt++))
        log "Attempt $attempt of $MAX_RETRIES..."
        
        # Method 1: Update desktoppicture.db for ALL displays
        local wallpaper_db="$HOME/Library/Application Support/Dock/desktoppicture.db"
        
        if [ -f "$wallpaper_db" ]; then
            # CRITICAL FIX: Update ALL entries, not just 'default'
            # External monitors have entries like 'default', '1', '2', etc.
            local escaped_path
            escaped_path=$(echo "$image_path" | sed "s/'/''/g")
            
            # First, update all existing entries
            sqlite3 "$wallpaper_db" "UPDATE data SET value = '$escaped_path';" 2>/dev/null
            
            # Second, ensure all displays have entries (insert if missing)
            local displays
            displays=$(sqlite3 "$wallpaper_db" "SELECT DISTINCT key FROM displays;" 2>/dev/null)
            
            if [ -z "$displays" ]; then
                # No displays table, just update data table
                sqlite3 "$wallpaper_db" "INSERT OR REPLACE INTO data (key, value) VALUES ('default', '$escaped_path');" 2>/dev/null
            else
                # Update each display entry
                for display_id in $displays; do
                    sqlite3 "$wallpaper_db" "UPDATE data SET value = '$escaped_path' WHERE rowid IN (SELECT data_id FROM displays WHERE key = '$display_id');" 2>/dev/null
                done
            fi
            
            log "Updated wallpaper database for all displays"
            
            # Kill Dock to apply changes
            killall Dock 2>/dev/null
            sleep 2
            
            # Verify the wallpaper was set
            local current_wp
            current_wp=$(get_current_wallpaper)
            if [ "$current_wp" = "$image_path" ]; then
                log "SUCCESS: Wallpaper verified on main display"
                return 0
            fi
        fi
        
        # Method 2: System Events (fallback)
        osascript <<EOF 2>/dev/null
            try
                tell application "System Events"
                    set picture of desktop 1 to POSIX file "$image_path"
                end tell
            end try
EOF
        sleep 1
        
        # Verify
        local current_wp
        current_wp=$(get_current_wallpaper)
        if [ "$current_wp" = "$image_path" ]; then
            log "SUCCESS: Wallpaper set via System Events"
            return 0
        fi
        
        log "Attempt $attempt failed, retrying in ${RETRY_DELAY}s..."
        sleep $RETRY_DELAY
    done
    
    log "ERROR: Failed to set wallpaper after $MAX_RETRIES attempts"
    return 1
}

# Get current wallpaper
get_current_wallpaper() {
    osascript -e 'try
        tell application "Finder"
            return POSIX path of (desktop picture as alias)
        end tell
    on error
        return ""
    end try' 2>/dev/null
}

# Set default wallpaper with retry
set_default_wallpaper() {
    log "Setting default wallpaper..."
    
    local default_wallpaper
    default_wallpaper=$(find_default_wallpaper)
    
    if [ -n "$default_wallpaper" ] && [ -f "$default_wallpaper" ]; then
        log "Using default wallpaper: $default_wallpaper"
        if set_wallpaper_stable "$default_wallpaper"; then
            log "Default wallpaper set successfully"
            return 0
        else
            log "ERROR: Failed to set default wallpaper"
            return 1
        fi
    else
        log "ERROR: No valid default wallpaper found"
        return 1
    fi
}

# Fetch JSON
fetch_json() {
    log "Fetching JSON from API: $API_URL"
    
    if ! curl -s -L --max-time $TIMEOUT -o "$JSON_CACHE_FILE" "$API_URL" 2>/dev/null; then
        log "ERROR: Failed to fetch JSON from API"
        rm -f "$JSON_CACHE_FILE"
        return 1
    fi
    
    if [ ! -f "$JSON_CACHE_FILE" ] || [ ! -s "$JSON_CACHE_FILE" ]; then
        log "ERROR: Downloaded JSON file is empty"
        rm -f "$JSON_CACHE_FILE"
        return 1
    fi
    
    if ! python3 -c "import sys, json; json.load(open('$JSON_CACHE_FILE'))" 2>/dev/null; then
        log "ERROR: Invalid JSON response"
        rm -f "$JSON_CACHE_FILE"
        return 1
    fi
    
    return 0
}

# Find wallpaper for date
find_wallpaper_for_date() {
    local target_date="$1"
    
    if [ ! -f "$JSON_CACHE_FILE" ]; then
        return 1
    fi
    
    python3 -c "
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
    sys.exit(1)
" 2>/dev/null
}

# Download and set wallpaper with full stability
download_and_set_wallpaper() {
    local image_url="$1"
    local filename="bing_wallpaper_$(date +%Y-%m-%d).jpg"
    local wallpaper_file="$WALLPAPER_DIR/$filename"
    
    log "Downloading wallpaper to: $wallpaper_file"
    
    # Download with retry
    local attempt=0
    while [ $attempt -lt $MAX_RETRIES ]; do
        ((attempt++))
        
        if curl -s -L --max-time $TIMEOUT -o "$wallpaper_file" "$image_url" 2>/dev/null; then
            break
        fi
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            log "Download attempt $attempt failed, retrying..."
            sleep $RETRY_DELAY
        else
            log "ERROR: Failed to download after $MAX_RETRIES attempts"
            return 1
        fi
    done
    
    # Verify download
    if [ ! -f "$wallpaper_file" ] || [ ! -s "$wallpaper_file" ]; then
        log "ERROR: Downloaded file is empty"
        return 1
    fi
    
    # Verify it's an image
    local file_type
    file_type=$(file -b "$wallpaper_file" 2>/dev/null)
    if [[ ! "$file_type" =~ (JPEG|JPG|PNG|image) ]]; then
        log "ERROR: Downloaded file is not a valid image: $file_type"
        return 1
    fi
    
    # Sync to disk before setting
    sync
    
    log "Downloaded successfully ($(stat -f%z "$wallpaper_file" 2>/dev/null || stat -c%s "$wallpaper_file" 2>/dev/null) bytes)"
    
    # Set wallpaper using stable method
    if set_wallpaper_stable "$wallpaper_file"; then
        log "SUCCESS: Wallpaper set"
        # Clean up old wallpapers (keep last 60 days)
        find "$WALLPAPER_DIR" -name "bing_wallpaper_*.jpg" -mtime +60 -delete 2>/dev/null
        return 0
    else
        log "ERROR: Failed to set wallpaper"
        return 1
    fi
}

# Get date N days ago
get_date_days_ago() {
    local days="$1"
    date -v-${days}d +%Y-%m-%d 2>/dev/null || date -d "${days} days ago" +%Y-%m-%d 2>/dev/null
}

# Main execution
main() {
    log "=== Bing Wallpaper Setter Started (ULTRA-STABLE) ==="
    
    if [ "$NO_FILTER" = true ]; then
        log "Mode: Filtering DISABLED"
    else
        log "Mode: Smart filtering ENABLED"
    fi
    
    # Check screen lock
    if is_screen_locked; then
        log "Skipping - screen is locked"
        exit 0
    fi
    
    # Check if already running
    if is_already_running; then
        log "Skipping - another instance is running"
        exit 0
    fi
    
    set_lock
    
    # Load filters
    load_filter_keywords
    
    # Save current wallpaper
    local current_wallpaper
    current_wallpaper=$(get_current_wallpaper)
    if [ -n "$current_wallpaper" ]; then
        log "Current wallpaper: $current_wallpaper"
    fi
    
    # Fetch JSON
    fetch_json
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to fetch JSON"
        set_default_wallpaper
        clear_lock
        exit 1
    fi
    
    # Get today's date
    local today
    today=$(date +%Y-%m-%d)
    log "Today's date: $today"
    
    # Find suitable wallpaper
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
                log "Found: $title"
                
                if check_wallpaper_filter "$title" "$description" "$caption"; then
                    selected_wallpaper="$url"
                    selected_title="$title"
                    selected_date="$target_date"
                    log "SELECTED: $target_date"
                    break
                else
                    log "Filtered out, trying previous day..."
                fi
            fi
        else
            log "No wallpaper found for: $target_date"
        fi
        
        ((days_back++))
    done
    
    # Set wallpaper
    if [ -n "$selected_wallpaper" ]; then
        log "Setting: $selected_title ($selected_date)"
        
        if download_and_set_wallpaper "$selected_wallpaper"; then
            log "=== SUCCESS: $selected_title ==="
            clear_lock
            exit 0
        else
            log "ERROR: Failed to set wallpaper"
            if [ -n "$current_wallpaper" ]; then
                set_wallpaper_stable "$current_wallpaper"
            fi
            set_default_wallpaper
            clear_lock
            exit 1
        fi
    else
        log "ERROR: No wallpaper found after $MAX_DAYS_BACK days"
        set_default_wallpaper
        clear_lock
        exit 1
    fi
}

# Cleanup
cleanup() {
    clear_lock
    rm -f "$JSON_CACHE_FILE"
}

trap cleanup EXIT

# Run
main
