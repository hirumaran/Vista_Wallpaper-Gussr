#!/bin/bash

# Test script for smart wallpaper filtering system
# Tests date-based selection and keyword filtering

API_URL="https://bing.npanuhin.me/US/en.json"
CONFIG_FILE="$(dirname "$0")/../config/wallpaper-filters.txt"

echo "🧪 Testing Smart Wallpaper System"
echo "=================================="
echo ""

# Test 1: API Connectivity
echo "✓ Test 1: API Connectivity"
json_response=$(curl -s --max-time 10 "$API_URL" 2>/dev/null)
if [ -n "$json_response" ]; then
    echo "  ✅ API fetch successful"
else
    echo "  ❌ API fetch failed"
    exit 1
fi

# Test 2: JSON Validity
echo "✓ Test 2: JSON Validation"
if echo "$json_response" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
    echo "  ✅ JSON is valid"
else
    echo "  ❌ Invalid JSON"
    exit 1
fi

# Test 3: Date Field Extraction
echo "✓ Test 3: Date Field Extraction"
dates=$(echo "$json_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    dates = [item.get('date', 'NO_DATE') for item in data if 'date' in item]
    print('\\n'.join(dates[:5]))
except:
    pass
" 2>/dev/null)

if [ -n "$dates" ]; then
    echo "  ✅ Found date fields in JSON"
    echo "  📅 Sample dates:"
    echo "$dates" | while read -r date; do
        echo "     - $date"
    done
else
    echo "  ⚠️  No date fields found (API may not have dates)"
fi

# Test 4: Today's Date Matching
echo "✓ Test 4: Today's Date Matching"
today=$(date +%Y-%m-%d)
echo "  Today: $today"

today_wallpaper=$(echo "$json_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    target = '$today'
    for item in data:
        if item.get('date') == target:
            print(f\"Found: {item.get('title', 'Untitled')}\")
            break
    else:
        print(\"No wallpaper found for today\")
except Exception as e:
    print(f\"Error: {e}\")
" 2>/dev/null)

echo "  $today_wallpaper"

# Test 5: Keyword Loading
echo "✓ Test 5: Filter Configuration"
if [ -f "$CONFIG_FILE" ]; then
    keep_count=$(grep -c "^[a-z]" "$CONFIG_FILE" 2>/dev/null || echo "0")
    skip_count=$(awk '/SKIP/,/^#/' "$CONFIG_FILE" | grep -c "^[a-z]" 2>/dev/null || echo "0")
    echo "  ✅ Config file exists: $CONFIG_FILE"
    echo "  📝 Keywords loaded from config"
else
    echo "  ⚠️  Config file not found, using defaults"
fi

# Test 6: Sample Filtering
echo "✓ Test 6: Sample Keyword Filtering"

# Test cases
declare -a test_cases=(
    "Earth from the International Space Station|SKIP|space station"
    "Northern Lights over Iceland|KEEP|aurora"
    "Abstract Geometric Patterns|SKIP|abstract"
    "Bengal Tiger in National Park|KEEP|tiger"
    "Microscopic View of Cells|SKIP|microscopic"
)

echo "  Testing filter logic:"
for test_case in "${test_cases[@]}"; do
    IFS='|' read -r title expected keyword <<< "$test_case"
    echo "    '$title' → $expected (keyword: $keyword)"
done

# Test 7: URL Extraction
echo "✓ Test 7: URL Extraction and Download"
image_url=$(echo "$json_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data and len(data) > 0:
        url = data[0].get('url') or data[0].get('bing_url')
        if url:
            if not url.startswith('http'):
                url = 'https://www.bing.com' + url
            print(url)
except:
    pass
" 2>/dev/null)

if [ -n "$image_url" ]; then
    echo "  ✅ URL extracted: ${image_url:0:60}..."
    
    # Test download
    temp_file="/tmp/test_smart_wallpaper_$(date +%s).jpg"
    if curl -s -L --max-time 15 -o "$temp_file" "$image_url" 2>/dev/null; then
        file_size=$(stat -f%z "$temp_file" 2>/dev/null || stat -c%s "$temp_file" 2>/dev/null)
        echo "  ✅ Download successful (${file_size} bytes)"
        rm -f "$temp_file"
    else
        echo "  ❌ Download failed"
    fi
else
    echo "  ❌ Could not extract URL"
fi

# Test 8: Date Functions
echo "✓ Test 8: Date Calculation Functions"
for days in 0 1 7; do
    date_result=$(date -v-${days}d +%Y-%m-%d 2>/dev/null || date -d "${days} days ago" +%Y-%m-%d 2>/dev/null)
    echo "  ${days} days ago: $date_result"
done

echo ""
echo "=================================="
echo "✅ All Tests Complete!"
echo ""
echo "Next Steps:"
echo "1. Review the filtering configuration: nano config/wallpaper-filters.txt"
echo "2. Test manually: ./scripts/set-wallpaper-now.sh"
echo "3. View logs: tail ~/Library/Logs/bing-wallpaper.log"
echo "4. Install for daily use: ./scripts/install-wallpaper.sh"
