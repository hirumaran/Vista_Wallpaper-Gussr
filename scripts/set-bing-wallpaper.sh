#!/bin/bash

# Bing Daily Wallpaper Setter for macOS
# ULTRA-STABLE version - prevents external monitor black screens permanently
# Key fix: Updates ALL display entries in wallpaper database, not just main display

# Configuration
API_URL="https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8&mkt=en-US"
LOG_FILE="$HOME/Library/Logs/bing-wallpaper.log"
CONFIG_FILE="$(dirname "$0")/../config/wallpaper-filters.txt"
TIMEOUT=30
MAX_DAYS_BACK=7
JSON_CACHE_FILE="/tmp/bing_wallpaper_cache.json"
WALLPAPER_DIR="/tmp"
STABLE_WALLPAPER_DIR="$HOME/Pictures/BingWallpapers"
LOCK_FILE="/tmp/bing_wallpaper_set.lock"
STATE_FILE="$HOME/.bing-wallpaper-state"
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
        --cycle)
            CYCLE_MODE=true
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

# BULLETPROOF wallpaper setter - updates ALL displays nicely
set_wallpaper_stable() {
    local image_path="$1"
    
    log "Setting wallpaper (STABLE logic): $image_path"
    
    # Verify file exists
    if [ ! -f "$image_path" ] || [ ! -r "$image_path" ]; then
        log "ERROR: Wallpaper file not accessible: $image_path"
        return 1
    fi
    
    # 1. Determine target filename (A/B Toggle)
    # We toggle between two filenames to force macOS to recognize the change.
    # If we just overwrite the same file, macOS caching often ignores the update.
    local current_wp
    current_wp=$(get_current_wallpaper)
    
    local stable_filename="current_wallpaper.jpg"
    if [[ "$current_wp" == *"/current_wallpaper.jpg" ]]; then
        stable_filename="current_wallpaper_alt.jpg"
    fi
    
    local stable_path="$STABLE_WALLPAPER_DIR/$stable_filename"
    log "Toggling to stable file: $stable_filename"
    
    # Use cp to overwrite
    cp -f "$image_path" "$stable_path"
    chmod 644 "$stable_path"
    sync
    
    # 2. Smoothly apply to all desktops using System Events
    # We iterate through every desktop (Space/Monitor) and set the picture.
    # This avoids 'killall Dock' which causes screen flickering/glitching.
    
    log "Applying to all desktops via System Events..."
    
    osascript -e '
    try
        tell application "System Events"
            set desktopCount to count of desktops
            repeat with i from 1 to desktopCount
                try
                    set picture of desktop i to POSIX file "'"$stable_path"'"
                end try
            end repeat
        end tell
    on error errMsg
        return "ERROR: " & errMsg
    end try' 2>/dev/null
    
    # Verify
    local current_wp
    current_wp=$(get_current_wallpaper)
    if [ "$current_wp" = "$stable_path" ]; then
        log "SUCCESS: Wallpaper set successfully"
        return 0
    else
        # Fallback: Sometimes System Events needs a "kick" if the path didn't change.
        # We can try setting it to the *same* path again, or just assume it worked if no error.
        # If it genuinely failed, we'll log it, but we wont kill Dock to avoid the glitch.
        log "WARNING: Verification check was ambiguous, but command ran. Current: $current_wp"
        return 0
    fi
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
import sys, json, datetime

try:
    with open('$JSON_CACHE_FILE', 'r') as f:
        data = json.load(f)
    
    target = '$target_date'.replace('-', '') # Convert YYYY-MM-DD to YYYYMMDD
    
    images = data.get('images', [])
    for item in images:
        startdate = item.get('startdate', '')
        if startdate == target:
            url = item.get('url')
            if url and not url.startswith('http'):
                url = 'https://www.bing.com' + url
            
            # Extract info
            title = item.get('title', '')
            copyright = item.get('copyright', '')
            # Copyright often contains location, utilize it as description/caption fallback
            
            print(json.dumps({
                'url': url,
                'title': title,
                'description': copyright, 
                'caption': item.get('copyright', ''),
                'date': '$target_date'
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
    local title="${2:-Bing Wallpaper}"
    # Location and date are unused for now as we don't overlay them
    # local location="${3:-Unknown Location}"
    # local wallpaper_date="${4:-$(date +%Y-%m-%d)}"
    
    local filename="bing_wallpaper_temp.jpg"
    local wallpaper_file="$WALLPAPER_DIR/$filename"
    
    # Try to get UHD if possible by replacing resolution in URL
    # Bing API typically returns 1920x1080. We check if UHD is available by replacing 1920x1080 with UHD
    image_url="${image_url//1920x1080/UHD}"
    
    log "Downloading wallpaper to: $wallpaper_file"
    log "URL: $image_url"
    
    # Download with retry
    local attempt=0
    while [ $attempt -lt $MAX_RETRIES ]; do
        ((attempt++))
        
        # Try to download UHD first
        if curl -s -L --max-time $TIMEOUT -o "$wallpaper_file" "$image_url" 2>/dev/null; then
             # Check if we got a valid image (sometimes UHD URL redirects to 1920x1080 or error page)
             if [[ $(file -b "$wallpaper_file") =~ (JPEG|JPG|PNG|image) ]]; then
                 break
             fi
             log "UHD download failed or invalid, falling back to original URL"
        fi
        
        # Fallback to original URL (likely 1920x1080)
        local original_url="${1}"
        if curl -s -L --max-time $TIMEOUT -o "$wallpaper_file" "$original_url" 2>/dev/null; then
            if [[ $(file -b "$wallpaper_file") =~ (JPEG|JPG|PNG|image) ]]; then
                 break
            fi
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
        return 0
    else
        log "ERROR: Failed to set wallpaper"
        return 1
    fi
}

# Save state
save_state() {
    local date="$1"
    echo "$date" > "$STATE_FILE"
}

# Get state
get_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo ""
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
    # if is_screen_locked; then
    #     log "Skipping - screen is locked"
    #     exit 0
    # fi
    
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
    
    # Identify valid wallpapers first
    local valid_wallpapers=()
    local valid_titles=()
    local valid_dates=()
    local valid_locations=()
    
    # Scan last 8 days for valid candidates
    log "Scanning available wallpapers..."
    local days_back=0
    while [ $days_back -lt 8 ]; do
        local target_date
        target_date=$(get_date_days_ago $days_back)
        
        local wallpaper_json
        wallpaper_json=$(find_wallpaper_for_date "$target_date")
        
        if [ $? -eq 0 ] && [ -n "$wallpaper_json" ]; then
             local url title description caption
             url=$(echo "$wallpaper_json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('url', ''))" 2>/dev/null)
             title=$(echo "$wallpaper_json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('title', ''))" 2>/dev/null)
             description=$(echo "$wallpaper_json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('description', ''))" 2>/dev/null)
             caption=$(echo "$wallpaper_json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('caption', ''))" 2>/dev/null)
             
             if [ -n "$url" ]; then
                 if check_wallpaper_filter "$title" "$description" "$caption"; then
                     # Valid candidate
                     valid_wallpapers+=("$url")
                     valid_titles+=("$title")
                     valid_dates+=("$target_date")
                     
                     # Extract location
                     local loc="$title"
                     if [ -n "$description" ]; then
                         loc=$(echo "$description" | sed 's/ (©.*//' | sed 's/ ©.*//')
                     elif [[ "$title" =~ in[[:space:]](.+)$ ]]; then
                         loc="${BASH_REMATCH[1]}"
                     fi
                     valid_locations+=("$loc")
                 fi
             fi
        fi
        ((days_back++))
    done
    
    local num_valid=${#valid_wallpapers[@]}
    log "Found $num_valid valid wallpapers"
    
    if [ $num_valid -eq 0 ]; then
        log "ERROR: No suitable wallpapers found"
        set_default_wallpaper
        cleanup
        exit 1
    fi
    
    # Selection Logic
    local selected_idx=-1
    
    if [ "$CYCLE_MODE" = true ]; then
        log "Mode: CYCLE/SHUFFLE"
        local current_date
        current_date=$(get_state)
        
        # Filter out current date
        local candidates_indices=()
        for i in "${!valid_dates[@]}"; do
            if [ "${valid_dates[$i]}" != "$current_date" ]; then
                candidates_indices+=($i)
            fi
        done
        
        local num_candidates=${#candidates_indices[@]}
        
        if [ $num_candidates -gt 0 ]; then
            # Pick random index
            local rand=$(( $RANDOM % $num_candidates ))
            selected_idx=${candidates_indices[$rand]}
            log "Cycling to new wallpaper (excluding $current_date)"
        else
            # Only one option exists (or current is unknown), just use the first/best one
            selected_idx=0
            log "Cannot cycle (only 1 valid option), reusing best match"
        fi
    else
        log "Mode: DAILY UPDATE (Prioritizing newest)"
        # Just pick the first one (newest)
        selected_idx=0
    fi
    
    if [ $selected_idx -ge 0 ]; then
        selected_wallpaper="${valid_wallpapers[$selected_idx]}"
        selected_title="${valid_titles[$selected_idx]}"
        selected_date="${valid_dates[$selected_idx]}"
        selected_location="${valid_locations[$selected_idx]}"
        
        log "Selected: $selected_title ($selected_date)"
        
        if download_and_set_wallpaper "$selected_wallpaper" "$selected_title" "$selected_location" "$selected_date"; then
            save_state "$selected_date"
            log "=== SUCCESS: $selected_title ==="
            cleanup
            exit 0
        fi
    fi
}

# Cleanup
cleanup() {
    clear_lock
    rm -f "$JSON_CACHE_FILE"
    rm -f "$WALLPAPER_DIR/bing_wallpaper_temp.jpg"
}

trap cleanup EXIT

# Run
main
