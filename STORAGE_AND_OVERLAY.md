# Storage & Text Overlay Features

## 📁 Where Are Images Stored?

### Primary Storage Location:
```
~/Pictures/BingWallpapers/
├── bing_wallpaper_2026-01-30.jpg          # Original downloaded image
├── overlay_2026-01-30.jpg                  # Image with text overlay
└── Stable/
    └── current_wallpaper.jpg               # Stable copy for all displays
```

### Directory Purposes:

**`~/Pictures/BingWallpapers/`**
- Stores all downloaded Bing wallpapers
- Stores overlay versions (with text) separately
- Retention: **7 days** (auto-deleted after 1 week)
- Each day gets its own file: `bing_wallpaper_YYYY-MM-DD.jpg`

**`~/Pictures/BingWallpapers/Stable/`**
- Contains `current_wallpaper.jpg`
- This file is **never auto-deleted**
- Used to prevent external monitor black screens
- All displays reference this stable file

## 🗑️ Retention Policy

### Automatic Cleanup (Every Run):
```bash
# Deletes files older than 7 days
find ~/Pictures/BingWallpapers/ -name "bing_wallpaper_*.jpg" -mtime +7 -delete
find ~/Pictures/BingWallpapers/ -name "overlay_*.jpg" -mtime +7 -delete
```

### What's Kept:
- ✅ Last 7 days of wallpapers
- ✅ Stable directory (permanent)
- ✅ Current wallpaper reference

### What's Deleted:
- ❌ Wallpapers older than 7 days
- ❌ Overlay files older than 7 days
- ❌ Temporary cache files

## ✨ Text Overlay Feature

### What It Does:
Automatically burns metadata into the wallpaper image at the **bottom left**:
- **Title** of the wallpaper
- **Location** (extracted from title)
- **Date** of the wallpaper

### Example Output:
```
St. Michael's Mount • Marazion, Cornwall, England • 2026-01-30
```

### Visual Style:
- **Position:** Bottom left corner
- **Font:** SF Pro (native macOS system font)
- **Size:** 16pt medium weight
- **Color:** White text
- **Background:** Semi-transparent black rounded rectangle
- **Padding:** 30px from edges
- **Retina:** Native 2x/3x support

### Technical Implementation:

**Tool:** `tools/WallpaperTextOverlay.swift`
- Written in **Swift** using **Core Graphics**
- Compiled binary: `tools/build/WallpaperTextOverlay` (71KB)
- Renders text natively using **CoreText**
- Full Retina display support
- Sub-pixel anti-aliasing

**Build Command:**
```bash
cd tools
swiftc -O -o build/WallpaperTextOverlay WallpaperTextOverlay.swift
```

**Usage:**
```bash
./tools/build/WallpaperTextOverlay \
  input.jpg \
  output.jpg \
  "Eiffel Tower" \
  "Paris, France" \
  "2026-01-30"
```

## 🔄 Workflow

### With Text Overlay:
```
1. Download wallpaper
   ↓
2. Extract metadata (title, location, date)
   ↓
3. Run Swift tool to burn text into image
   ↓
4. Save overlay version: overlay_YYYY-MM-DD.jpg
   ↓
5. Set as wallpaper (ALL displays)
   ↓
6. Cleanup: Keep last 7 days only
```

### File Lifecycle:
```
Day 1: Download → Create overlay → Set wallpaper → Keep
Day 2: Download → Create overlay → Set wallpaper → Keep
...
Day 8: Download → Create overlay → Set wallpaper → Keep
       ↓
       Auto-delete Day 1 files
```

## 💾 Storage Calculation

### Per Wallpaper:
- Original: ~3-4 MB
- Overlay: ~3-4 MB
- **Total per day:** ~6-8 MB

### 7-Day Retention:
- **Maximum storage:** ~42-56 MB
- **Stable directory:** Always keeps current (3-4 MB)
- **Total:** ~46-60 MB maximum

### To Check Current Usage:
```bash
# See all stored wallpapers
ls -lh ~/Pictures/BingWallpapers/

# Check total size
du -sh ~/Pictures/BingWallpapers/

# Count files
find ~/Pictures/BingWallpapers/ -name "*.jpg" | wc -l
```

## ⚙️ Customization

### Disable Text Overlay:
Currently enabled by default. To disable, edit `scripts/set-bing-wallpaper.sh`:

Comment out or remove this section:
```bash
# Add text overlay using Swift tool
local text_overlay_tool="$(dirname "$0")/../tools/build/WallpaperTextOverlay"
if [ -f "$text_overlay_tool" ] && [ -x "$text_overlay_tool" ]; then
    ...
fi
```

### Change Retention Period:
Edit `scripts/set-bing-wallpaper.sh`:

Change `+7` to your preferred number of days:
```bash
# Keep last X days (change the number)
find "$WALLPAPER_DIR" -name "bing_wallpaper_*.jpg" -mtime +7 -delete
```

### Change Text Position/Style:
Edit `tools/WallpaperTextOverlay.swift`:

**Position:**
```swift
// Change these values
let padding: CGFloat = 30  // Distance from edges
let textRect = CGRect(
    x: padding,  // Left position
    y: padding,  // Bottom position
    width: textSize.width + 20,
    height: textSize.height + 16
)
```

**Style:**
```swift
// Font size
let fontSize: CGFloat = 16

// Background opacity (0.0 = transparent, 1.0 = solid)
CGColor(red: 0, green: 0, blue: 0, alpha: 0.6)

// Corner radius
CGPath(roundedRect: textRect, cornerWidth: 8, cornerHeight: 8)
```

Then rebuild:
```bash
cd tools
./build.sh
```

## 🎯 Benefits

### 7-Day Retention:
- ✅ Balances storage vs. history
- ✅ Keeps recent wallpapers accessible
- ✅ Auto-cleanup prevents disk bloat
- ✅ Stable copy ensures no black screens

### Text Overlay:
- ✅ Shows wallpaper metadata at a glance
- ✅ Native macOS rendering (SF Pro font)
- ✅ Retina-optimized
- ✅ Non-intrusive (bottom left corner)
- ✅ Professional appearance

## 🔍 Verification

### Check Everything Works:
```bash
# 1. Verify storage location
ls -la ~/Pictures/BingWallpapers/

# 2. Check text overlay tool exists
ls -la ~/Documents/bg_spot/tools/build/WallpaperTextOverlay

# 3. Test overlay tool
~/Documents/bg_spot/tools/build/WallpaperTextOverlay

# 4. View logs
tail ~/Library/Logs/bing-wallpaper.log | grep -E "(overlay|text|Adding text)"

# 5. Check disk usage
du -sh ~/Pictures/BingWallpapers/
```

## 📝 Summary

| Feature | Location | Retention |
|---------|----------|-----------|
| Original wallpapers | `~/Pictures/BingWallpapers/` | 7 days |
| Overlay versions | `~/Pictures/BingWallpapers/` | 7 days |
| Stable reference | `~/Pictures/BingWallpapers/Stable/` | Permanent |
| Text overlay tool | `tools/build/WallpaperTextOverlay` | Permanent |
| Swift source | `tools/WallpaperTextOverlay.swift` | Permanent |

**Total disk usage:** ~50-60 MB maximum
**Text overlay:** Bottom left, white text on dark background
**Font:** SF Pro (native macOS)
