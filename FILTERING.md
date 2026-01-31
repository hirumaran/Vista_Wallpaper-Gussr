# Smart Wallpaper Filtering System

The Bing Wallpaper Setter now includes intelligent filtering to ensure you get beautiful, scenic wallpapers instead of abstract or technical images.

## How Smart Filtering Works

### 1. Date-Based Selection

The script automatically finds the wallpaper for today's date:

```
Today's Date: 2026-01-30
↓
Search JSON for "date": "2026-01-30"
↓
Apply filters
↓
Set as wallpaper
```

**If today's wallpaper is filtered out**, the script automatically tries:
- Yesterday's wallpaper
- Day before yesterday
- Up to 7 days back
- Uses the first wallpaper that passes the filter

### 2. Keyword Filtering

Each wallpaper is evaluated based on its **title**, **description**, and **caption**.

#### Skip Keywords (Rejected)
These keywords indicate wallpapers that are usually boring or not suitable for daily wallpapers:

**Space/Satellite Images**
- earth from space
- satellite view/image
- space station
- international space station (ISS)
- NASA, orbit, planetary

**Abstract/Artistic**
- abstract, abstract art
- artistic pattern, geometric
- fractal, digital art
- illustration, graphic design
- conceptual art, modern art

**Scientific/Microscopic**
- microscopic, microscope
- cellular, cell, bacteria
- virus, molecule, atom

**Diagrams/Infographics**
- diagram, infographic
- chart, graph
- map, cartography

**Random/Still Life**
- still life, random objects
- everyday objects, collection

**Dark/Minimalist**
- minimalist, solid color
- dark/black background

#### Keep Keywords (Preferred)
These keywords indicate beautiful scenic wallpapers:

**Nature & Landscapes**
- mountain, mountains, beach, ocean
- forest, island, lake, river
- waterfall, valley, canyon
- glacier, volcano

**Wildlife & Animals**
- wildlife, animal, bird
- elephant, tiger, lion, leopard
- whale, dolphin, penguin
- polar bear, giraffe, zebra

**Architecture & Historic**
- castle, palace, temple
- church, cathedral, mosque
- architecture, historic, ancient
- ruins, monument, landmark

**Scenic & Tourism**
- national park, landscape
- scenic, nature, natural
- wonder, reserve

**Natural Phenomena**
- aurora, sunset, sunrise
- rainbow, mist, fog
- autumn, winter, snow
- cherry blossom

## Configuration

### Customizing Filters

Edit the config file at `config/wallpaper-filters.txt`:

```bash
# Open the config file
nano config/wallpaper-filters.txt
```

**Format:**
```
# Comments start with #
# Add keywords one per line

# KEEP section - wallpapers with these are preferred
mountain
beach
sunset
aurora
wildlife

# SKIP section - wallpapers with these are rejected
abstract
satellite
microscopic
diagram
```

### Disabling Filters

To temporarily disable filtering and get ALL wallpapers:

```bash
# Manual run without filtering
./scripts/set-wallpaper-now.sh --no-filter

# Or run the main script directly
./scripts/set-bing-wallpaper.sh --no-filter
```

## Filtering Examples

### ✅ Good Wallpapers (Will Be Kept)

**St. Michael's Mount in Cornwall, England**
- Contains: "island", "coast"
- Result: ✅ USED

**Bengal Tiger in Ranthambore National Park**
- Contains: "tiger", "wildlife", "national park"
- Result: ✅ USED

**Sunset over the Grand Canyon**
- Contains: "sunset", "canyon"
- Result: ✅ USED

### ❌ Bad Wallpapers (Will Be Skipped)

**Earth from the International Space Station**
- Contains: "earth from space", "space station"
- Result: ❌ SKIPPED
- Action: Script tries yesterday's wallpaper

**Abstract Geometric Patterns**
- Contains: "abstract", "geometric"
- Result: ❌ SKIPPED
- Action: Script tries yesterday's wallpaper

**Microscopic View of Bacteria**
- Contains: "microscopic", "bacteria"
- Result: ❌ SKIPPED
- Action: Script tries yesterday's wallpaper

## Logging

The script logs all filtering decisions:

```bash
# View recent filtering decisions
tail -f ~/Library/Logs/bing-wallpaper.log | grep -E "(FILTER|SELECTED|Skipped)"
```

**Example log output:**
```
[2026-01-30 08:00:01] Looking for wallpaper with date: 2026-01-30
[2026-01-30 08:00:02] Found wallpaper: Earth from the ISS
[2026-01-30 08:00:02] FILTER: SKIPPED - Contains skip keyword: 'space station'
[2026-01-30 08:00:02]   Title: Earth from the ISS
[2026-01-30 08:00:03] Checking date: 2026-01-29 (1 days ago)
[2026-01-30 08:00:03] Found wallpaper: Northern Lights in Iceland
[2026-01-30 08:00:03] FILTER: PASSED - No skip keywords found
[2026-01-30 08:00:03] SELECTED: Using wallpaper from 2026-01-29
[2026-01-30 08:00:04] Setting wallpaper: Northern Lights in Iceland (2026-01-29)
[2026-01-30 08:00:05] SUCCESS: Wallpaper set from downloaded file
```

## Advanced Configuration

### Adding Custom Keywords

1. Open `config/wallpaper-filters.txt`
2. Add your keywords to the appropriate section
3. Save the file
4. Run the script again

**Example - Adding "beach volleyball" to skip:**
```
# In the SKIP section, add:
beach volleyball
sports
stadium
```

**Example - Adding "waterfall" to prefer:**
```
# In the KEEP section, add:
waterfall
waterfalls
misty
```

### Case Sensitivity

Keywords are matched **case-insensitively**, so:
- "Mountain" matches "mountain", "MOUNTAIN", "Mountain"
- "Abstract Art" matches "abstract art", "ABSTRACT ART"

### Partial Matching

Keywords match partial words by default:
- "mountain" matches "mountains", "mountainous", "mountaintop"
- "bird" matches "birds", "birdwatching", "hummingbird"

## Troubleshooting

### Getting Too Many Skipped Wallpapers?

If you notice the script is going back several days frequently:

1. Check the logs to see which keywords are triggering skips
2. Edit `config/wallpaper-filters.txt` to remove overly broad keywords
3. Or use `--no-filter` to disable filtering temporarily

### Want More Variety?

The API may not have wallpapers for every day. The script will:
1. Try today's date
2. Go back up to 7 days
3. Use the most recent beautiful wallpaper available

### Filter Not Working?

1. Check that `config/wallpaper-filters.txt` exists
2. Verify the file has both KEEP and SKIP sections
3. Check logs for "Loaded X keep keywords and Y skip keywords"
4. Ensure keywords are one per line (no quotes needed)

## Integration with Vista Game

The filtering system only affects the wallpaper setter script. Your Vista game in `index.html`:
- Continues to show all wallpapers (no filtering)
- Is completely independent of the wallpaper setter
- Can be used while the auto-wallpaper runs in background

## Command Reference

```bash
# Set wallpaper with smart filtering (default)
./scripts/set-wallpaper-now.sh

# Set wallpaper without filtering
./scripts/set-wallpaper-now.sh --no-filter

# View filtering logs
grep "FILTER" ~/Library/Logs/bing-wallpaper.log

# Edit filter configuration
nano config/wallpaper-filters.txt

# Check which keywords are loaded
./scripts/set-wallpaper-now.sh 2>&1 | grep "Loaded"
```

## Future Enhancements

Potential future improvements:
- AI-based image analysis (instead of keyword matching)
- User feedback system (thumbs up/down to improve filtering)
- Category preferences (only nature, only animals, etc.)
- Seasonal keyword adjustments
- Wallpaper quality scoring based on resolution and composition
