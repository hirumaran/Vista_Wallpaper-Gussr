#!/bin/bash

# Build script for WallpaperTextOverlay Swift tool
# Compiles the Swift tool for adding text to wallpapers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR"
BUILD_DIR="$TOOLS_DIR/build"

echo "🔨 Building WallpaperTextOverlay..."
echo ""

# Create build directory
mkdir -p "$BUILD_DIR"

# Compile Swift code
cd "$TOOLS_DIR"
swiftc -O -o "$BUILD_DIR/WallpaperTextOverlay" WallpaperTextOverlay.swift

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "Binary: $BUILD_DIR/WallpaperTextOverlay"
    echo ""
    echo "Usage:"
    echo "  $BUILD_DIR/WallpaperTextOverlay <input> <output> <title> <location> <date>"
    echo ""
    echo "Example:"
    echo "  $BUILD_DIR/WallpaperTextOverlay input.jpg output.jpg 'Eiffel Tower' 'Paris, France' '2026-01-30'"
else
    echo "❌ Build failed"
    exit 1
fi
