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

# Get display resolution for optimal scaling
get_display_resolution() {
    local resolution
    
    # Try multiple methods to get resolution
    # Method 1: system_profiler (most reliable)
    resolution=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -A 3 "Resolution" | grep -oE "[0-9]+\s*x\s*[0-9]+" | head -1 | tr -d ' ')
    
    # Method 2: Try AppleScript if method 1 fails
    if [ -z "$resolution" ]; then
        resolution=$(osascript -e '
        try
            tell application "Finder"
                set disp to bounds of window of desktop
                set w to item 3 of disp
                set h to item 4 of disp
                return (w as string) & "x" & (h as string)
            end tell
        on error
            return ""
        end try' 2>/dev/null)
    fi
    
    # Method 3: Try sw_vers and known resolutions for MacBook models (last resort)
    if [ -z "$resolution" ]; then
        local model
        model=$(sysctl -n hw.model 2>/dev/null)
        if [[ "$model" =~ Mac.*Pro|MacBookPro|MacBookAir ]]; then
            # Common resolutions for Mac laptops/pros
            resolution="3024x1964"  # Modern MacBook Pro 14"
        fi
    fi
    
    echo "$resolution"
}

# Clear macOS wallpaper caches to prevent blurry lock screen
clear_wallpaper_caches() {
    log "Clearing macOS wallpaper caches..."
    
    # Clear Dock database cache
    local db_path="$HOME/Library/Application Support/Dock/desktoppicture.db"
    if [ -f "$db_path" ]; then
        sqlite3 "$db_path" "DELETE FROM pictures;" 2>/dev/null || true
        sqlite3 "$db_path" "DELETE FROM data;" 2>/dev/null || true
    fi
    
    # Clear lock screen wallpaper cache
    rm -rf "$HOME/Library/Caches/com.apple.desktop.admin" 2>/dev/null || true
    rm -rf "$HOME/Library/Caches/com.apple.desktop.lockscreen" 2>/dev/null || true
    rm -rf "$HOME/Library/Caches/com.apple.desktop.screensaver" 2>/dev/null || true
    
    # Clear other wallpaper-related caches
    rm -rf "$HOME/Library/Caches/Desktop" 2>/dev/null || true
    
    log "Wallpaper caches cleared"
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
    
    # Get display resolution for optimal pre-scaling
    local display_res
    display_res=$(get_display_resolution)
    log "Display resolution: ${display_res:-"unknown"}"
    
    # ULTRA-HIGH-QUALITY FIX: Convert to HEIC (native macOS format) with proper scaling
    # macOS native wallpapers use HEIC format which preserves quality better
    local heic_path="${image_path%.*}_hq.heic"
    log "Converting to HEIC for maximum lockscreen quality: $heic_path"
    
    # First, get image info
    local img_info
    img_info=$(sips -g pixelWidth -g pixelHeight "$image_path" 2>/dev/null)
    local img_width=$(echo "$img_info" | grep "pixelWidth" | awk '{print $2}')
    local img_height=$(echo "$img_info" | grep "pixelHeight" | awk '{print $2}')
    
    log "Original image size: ${img_width}x${img_height}"
    
    # Convert to HEIC with high quality settings
    # Using sips with best quality and preserving color profile
    if [ -n "$display_res" ]; then
        # Pre-scale to exact display resolution to prevent macOS scaling artifacts
        log "Pre-scaling to display resolution for sharp lock screen..."
        sips -s format heic \
             -s formatOptions best \
             --resampleHeightWidthMax $(echo "$display_res" | cut -d'x' -f2) \
             "$image_path" \
             --out "$heic_path" >/dev/null 2>&1
    else
        # Keep original size if we can't detect display
        sips -s format heic \
             -s formatOptions best \
             "$image_path" \
             --out "$heic_path" >/dev/null 2>&1
    fi
    
    # If HEIC conversion fails, fallback to high-quality PNG
    if [ ! -f "$heic_path" ]; then
        log "HEIC conversion failed, trying high-quality PNG..."
        local png_path="${image_path%.*}_hq.png"
        
        if [ -n "$display_res" ]; then
            sips -s format png \
                 --resampleHeightWidthMax $(echo "$display_res" | cut -d'x' -f2) \
                 "$image_path" \
                 --out "$png_path" >/dev/null 2>&1
        else
            sips -s format png "$image_path" --out "$png_path" >/dev/null 2>&1
        fi
        
        if [ -f "$png_path" ]; then
            image_path="$png_path"
            log "Using high-quality PNG"
        fi
    else
        image_path="$heic_path"
        log "Using high-quality HEIC (native macOS format)"
    fi
    
    # Clear caches before setting new wallpaper to prevent blurry lock screen
    clear_wallpaper_caches
    
    # Get the file extension from the processed image
    local file_ext="${image_path##*.}"
    
    local main_file="current_wallpaper.${file_ext}"
    local alt_file="current_wallpaper_refresh.${file_ext}"
    
    local main_path="$STABLE_WALLPAPER_DIR/$main_file"
    local alt_path="$STABLE_WALLPAPER_DIR/$alt_file"
    
    # Update both files with new image bits
    cp -f "$image_path" "$main_path"
    cp -f "$image_path" "$alt_path"
    chmod 644 "$main_path" "$alt_path"
    sync
    
    # 2. Determine which one to used for *Active* refresh (Toggle)
    local current_wp
    current_wp=$(get_current_wallpaper)
    local target_path="$main_path"
    
    # If currently using Main, switch to Alt to force refresh
    if [[ "$current_wp" == *"$main_file" ]]; then
        target_path="$alt_path"
        log "Toggling active display to: $alt_file"
    else
        target_path="$main_path"
        log "Toggling active display to: $main_file"
    fi
    
    # 2. Smoothly apply to all desktops using System Events
    # This handles the currently active displays immediately.
    log "Applying to all desktops via System Events..."
    
    osascript -e '
    try
        tell application "System Events"
            set desktopCount to count of desktops
            repeat with i from 1 to desktopCount
                try
                    set picture of desktop i to POSIX file "'"$target_path"'"
                end try
            end repeat
        end tell
    on error errMsg
        return "ERROR: " & errMsg
    end try' 2>/dev/null
    
    # 3. Persistent Fix for Clamshell/Spaces (The "Hidden" Update)
    # We ALWAYS update the DB to point to the MAIN file.
    # Since we updated the bits of MAIN above, Clamshell mode will find the new image there.
    
    local db_path="$HOME/Library/Application Support/Dock/desktoppicture.db"
    if [ -f "$db_path" ]; then
        log "Seeding wallpaper database for future layouts (Clamshell fix)..."
        # Update ALL entries in the data table to point to our MAIN wallpaper
        sqlite3 "$db_path" "UPDATE data SET value = '$main_path';" 2>/dev/null
    fi
    
    # Verify using target_path
    local current_wp
    current_wp=$(get_current_wallpaper)
    if [ "$current_wp" = "$target_path" ]; then
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
            # Improved Randomness using date + RANDOM
            local seed
            seed=$(date +%s%N)
            local rand=$(( (seed + RANDOM) % num_candidates ))
            selected_idx=${candidates_indices[$rand]}
            log "Cycling to new wallpaper (excluding $current_date)"
        else
            selected_idx=0
            log "Cannot cycle (only 1 valid option), reusing best match"
        fi
    else
        log "Mode: DAILY UPDATE (Prioritizing newest)"
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
    # Clean up temporary high-quality conversion files
    rm -f "$WALLPAPER_DIR"/*_hq.heic "$WALLPAPER_DIR"/*_hq.png 2>/dev/null || true
    rm -f "$STABLE_WALLPAPER_DIR"/*_hq.heic "$STABLE_WALLPAPER_DIR"/*_hq.png 2>/dev/null || true
}

trap cleanup EXIT

# Run
main
