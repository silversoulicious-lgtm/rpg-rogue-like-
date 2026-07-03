#!/bin/bash

# Godot 4.3 Headless Downloader
# This script downloads the Godot 4.3 stable headless version for Linux x86_64

set -e

GODOT_VERSION="4.3"
GODOT_BINARY_NAME="Godot_v4.3-stable_linux.x86_64_headless"
DOWNLOAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try multiple download mirrors
MIRRORS=(
    "https://github.com/godotengine/godot/releases/download/4.3-stable/${GODOT_BINARY_NAME}.tar.xz"
    "https://downloads.tuxfamily.org/godotengine/4.3/${GODOT_BINARY_NAME}.tar.xz"
)

echo "Godot 4.3 Headless Downloader"
echo "==============================="
echo "Download directory: $DOWNLOAD_DIR"
echo ""

OUTPUT_FILE="$DOWNLOAD_DIR/${GODOT_BINARY_NAME}.tar.xz"

# Check if file already exists
if [ -f "$OUTPUT_FILE" ]; then
    FILE_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "unknown")
    echo "✓ File already exists: $OUTPUT_FILE ($FILE_SIZE bytes)"
    echo ""
    echo "To re-download, run:"
    echo "  rm '$OUTPUT_FILE' && $0"
    exit 0
fi

echo "Attempting to download Godot 4.3 headless..."
echo ""

DOWNLOADED=0
for MIRROR in "${MIRRORS[@]}"; do
    echo "Trying: $MIRROR"
    if curl -L --progress-bar -o "$OUTPUT_FILE" "$MIRROR" 2>/dev/null; then
        FILE_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null)
        if [ "$FILE_SIZE" -gt 100000000 ]; then  # Should be ~200MB
            echo "✓ Downloaded successfully!"
            DOWNLOADED=1
            break
        else
            echo "✗ Downloaded file seems too small ($FILE_SIZE bytes)"
            rm -f "$OUTPUT_FILE"
        fi
    fi
done

if [ $DOWNLOADED -eq 1 ]; then
    echo ""
    echo "File saved to: $OUTPUT_FILE"
    echo "File size: $(numfmt --to=iec-i --suffix=B $FILE_SIZE 2>/dev/null || echo $FILE_SIZE bytes)"
    echo ""
    echo "To extract:"
    echo "  cd $(dirname "$OUTPUT_FILE")"
    echo "  tar -xf $(basename "$OUTPUT_FILE")"
    echo ""
    echo "This will create the godot binary in the same directory."
else
    echo "✗ Failed to download from all mirrors"
    echo ""
    echo "Try downloading manually from:"
    for MIRROR in "${MIRRORS[@]}"; do
        echo "  - $MIRROR"
    done
    exit 1
fi
