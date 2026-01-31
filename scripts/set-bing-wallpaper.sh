#!/bin/bash

# Bing Daily Wallpaper Setter for macOS
# Fetches the daily wallpaper from Bing with smart filtering and date-based selection
# Downloads wallpaper temporarily, sets it, then cleans up

# Configuration
API_URL="https://bing.npanuhin.me/US/en.json"
LOG_FILE="$HOME/Library/Logs/bing-wallpaper.log"
CONFIG_FILE="$(dirname "$0")/../config/wallpaper-filters.txt"
TIMEOUT=30
MAX_DAYS_BACK=7
JSON_CACHE_FILE="/tmp/bing_wallpaper_cache.json"
WALLPAPER_DIR="$HOME/Pictures/BingWallpapers"

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

# Load filter keywords from config file
load_filter_keywords() {
    KEEP_KEYWORDS=()
    SKIP_KEYWORDS=()
    
    if [ -f "$CONFIG_FILE" ]; then
        local section=""
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip empty lines
            [[ -z "$line" ]] && continue

            # Detect section headers (which are also comments)
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

# Check if wallpaper passes the filter
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
    
    # Check keep keywords (optional - could require at least one keep keyword)
    # For now, we'll accept it if it doesn't have skip keywords
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

# Function to set wallpaper from local file
# Function to set wallpaper from local file
set_wallpaper_from_file() {
    local image_path="$1"
    
    log "Setting wallpaper from local file: $image_path"
    
    # Try System Events first (better for modern macOS / multiple spaces)
    osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$image_path\"" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "success"
        return 0
    fi
    
    # Fallback to Finder if System Events fails
    osascript <<EOF
        try
            tell application "Finder"
                set desktop picture to POSIX file "$image_path"
            end tell
            return "success"
        on error errMsg
            return "error: " & errMsg
        end try
EOF
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
        
        if [[ "$result" == *"success"* ]]; then
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
# Note: JSON is ~4.7MB which exceeds bash ARG_MAX limit (~1MB),
# so we save to a temp file instead of passing as argument
fetch_json() {
    log "Fetching JSON from API: $API_URL"
    
    # Download directly to cache file
    if ! curl -s -L --max-time $TIMEOUT -o "$JSON_CACHE_FILE" "$API_URL" 2>/dev/null; then
        log "ERROR: Failed to fetch JSON from API (timeout or network error)"
        rm -f "$JSON_CACHE_FILE"
        return 1
    fi
    
    # Check if file exists and is not empty
    if [ ! -f "$JSON_CACHE_FILE" ] || [ ! -s "$JSON_CACHE_FILE" ]; then
        log "ERROR: Downloaded JSON file is empty or missing"
        rm -f "$JSON_CACHE_FILE"
        return 1
    fi
    
    # Validate JSON format
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

# Function to find wallpaper for specific date with filtering
# Reads from JSON_CACHE_FILE instead of accepting JSON as argument
# NOTE: Uses file-only logging to not pollute stdout with log messages
find_wallpaper_for_date() {
    local target_date="$1"
    
    # Log directly to file only (not stdout) to avoid polluting return value
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Looking for wallpaper with date: $target_date" >> "$LOG_FILE"
    
    # Check if cache file exists
    if [ ! -f "$JSON_CACHE_FILE" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: JSON cache file not found" >> "$LOG_FILE"
        return 1
    fi
    
    # Use Python to find the wallpaper for this date from the cache file
    local wallpaper_info
    wallpaper_info=$(python3 -c "
import sys, json
try:
    with open('$JSON_CACHE_FILE', 'r') as f:
        data = json.load(f)
    target = '$target_date'
    
    # Find entry matching the date
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
    
    # Date not found
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

# Function to get all available dates from JSON cache file
get_available_dates() {
    if [ ! -f "$JSON_CACHE_FILE" ]; then
        return 1
    fi
    
    python3 -c "
import json
try:
    with open('$JSON_CACHE_FILE', 'r') as f:
        data = json.load(f)
    dates = []
    for item in data:
        if 'date' in item:
            dates.append(item['date'])
    # Sort dates descending (newest first)
    dates.sort(reverse=True)
    for d in dates[:20]:  # Return top 20 most recent dates
        print(d)
except Exception as e:
    pass
" 2>/dev/null
}

# Function to download and set wallpaper
# Function to download and set wallpaper
download_and_set_wallpaper() {
    local image_url="$1"
    # Use persistent path so wallpaper stays set
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
    
    # DO NOT delete the file, macOS needs it to persist
    
    if [[ "$result" == *"success"* ]]; then
        log "SUCCESS: Wallpaper set from downloaded file"
        # Optional: Clean up old wallpapers (keep last 30 days)
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
    
    # Load filter keywords
    load_filter_keywords
    
    # Save current wallpaper for potential restore
    local current_wallpaper
    current_wallpaper=$(get_current_wallpaper)
    if [ -n "$current_wallpaper" ]; then
        log "Current wallpaper saved: $current_wallpaper"
    fi
    
    # Fetch JSON data (saves to JSON_CACHE_FILE)
    fetch_json
    
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to fetch JSON data"
        if [ -n "$current_wallpaper" ] && [ -f "$current_wallpaper" ]; then
            set_wallpaper_from_file "$current_wallpaper"
        fi
        set_default_wallpaper
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
            # Extract wallpaper details
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
            exit 0
        else
            log "ERROR: Failed to set selected wallpaper"
            if [ -n "$current_wallpaper" ] && [ -f "$current_wallpaper" ]; then
                log "Restoring previous wallpaper..."
                set_wallpaper_from_file "$current_wallpaper"
            fi
            set_default_wallpaper
            exit 1
        fi
    else
        log "ERROR: No suitable wallpaper found after checking $MAX_DAYS_BACK days"
        if [ -n "$current_wallpaper" ] && [ -f "$current_wallpaper" ]; then
            set_wallpaper_from_file "$current_wallpaper"
        fi
        set_default_wallpaper
        exit 1
    fi
}

# Cleanup function to remove cache file
cleanup() {
    rm -f "$JSON_CACHE_FILE"
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Run main function
main
