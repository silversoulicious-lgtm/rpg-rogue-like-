#!/usr/bin/env python3
"""
Godot 4.3 Headless Downloader

Downloads the Godot 4.3 stable headless version for Linux x86_64
"""

import os
import sys
import urllib.request
import urllib.error
import ssl
import time
from pathlib import Path

GODOT_VERSION = "4.3"
GODOT_FILENAME = "Godot_v4.3-stable_linux.x86_64_headless.tar.xz"

# Try multiple mirrors in order
MIRRORS = [
    "https://github.com/godotengine/godot/releases/download/4.3-stable/",
    "https://downloads.tuxfamily.org/godotengine/4.3/",
]

def format_bytes(bytes_val):
    """Format bytes to human readable format"""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if bytes_val < 1024:
            return f"{bytes_val:.1f} {unit}"
        bytes_val /= 1024
    return f"{bytes_val:.1f} TB"

def download_file(url, output_path, max_retries=3):
    """Download a file with retry logic"""

    for attempt in range(max_retries):
        try:
            print(f"\nAttempt {attempt + 1}/{max_retries}")
            print(f"Downloading from: {url}")

            # Create SSL context with proper CA bundle
            ctx = ssl.create_default_context()
            ca_bundle = "/root/.ccr/ca-bundle.crt"
            if os.path.exists(ca_bundle):
                ctx.load_verify_locations(ca_bundle)

            # Download with progress
            total_size = 0
            chunk_size = 1024 * 1024  # 1MB

            class ProgressBar:
                def __init__(self):
                    self.last_update = 0

                def update(self, current, total):
                    now = time.time()
                    if now - self.last_update > 0.5:  # Update every 0.5s
                        if total > 0:
                            percent = (current / total) * 100
                            mb_current = current / (1024 * 1024)
                            mb_total = total / (1024 * 1024)
                            print(f"\r  [{percent:5.1f}%] {mb_current:7.1f} / {mb_total:7.1f} MB", end='', flush=True)
                        self.last_update = now

            progress = ProgressBar()

            with urllib.request.urlopen(url, context=ctx, timeout=30) as response:
                total_size = int(response.headers.get('Content-Length', 0))

                with open(output_path, 'wb') as f:
                    downloaded = 0
                    while True:
                        chunk = response.read(chunk_size)
                        if not chunk:
                            break
                        f.write(chunk)
                        downloaded += len(chunk)
                        if total_size > 0:
                            progress.update(downloaded, total_size)

            # Verify file
            file_size = os.path.getsize(output_path)
            print(f"\n✓ Downloaded successfully!")
            print(f"  File size: {format_bytes(file_size)}")

            # Check if it's a valid XZ archive
            with open(output_path, 'rb') as f:
                header = f.read(6)
                if header[:2] == b'\xfd7':  # XZ magic number
                    print(f"✓ Valid XZ archive format")
                    return True
                else:
                    print(f"✗ File does not appear to be a valid XZ archive")
                    return False

        except urllib.error.HTTPError as e:
            print(f"✗ HTTP Error {e.code}: {e.reason}")
            if e.code == 403:
                print("  (Forbidden - network policy may be restricting access)")
        except urllib.error.URLError as e:
            print(f"✗ Connection error: {e.reason}")
        except socket.timeout:
            print(f"✗ Connection timeout")
        except Exception as e:
            print(f"✗ Error: {e}")

        if attempt < max_retries - 1:
            wait_time = 2 ** attempt  # Exponential backoff
            print(f"  Retrying in {wait_time} seconds...")
            time.sleep(wait_time)

    return False

def main():
    # Create tools directory if it doesn't exist
    script_dir = Path(__file__).parent
    os.makedirs(script_dir, exist_ok=True)

    output_file = script_dir / GODOT_FILENAME

    print("=" * 60)
    print("Godot 4.3 Headless Downloader")
    print("=" * 60)
    print(f"Download directory: {script_dir}")
    print(f"Output file: {output_file.name}")
    print()

    # Check if file already exists
    if output_file.exists():
        file_size = output_file.stat().st_size
        print(f"✓ File already exists!")
        print(f"  Path: {output_file}")
        print(f"  Size: {format_bytes(file_size)}")
        print()
        print("To re-download, delete the file first:")
        print(f"  rm {output_file}")
        return 0

    # Try each mirror
    success = False
    for mirror_base in MIRRORS:
        url = mirror_base + GODOT_FILENAME
        if download_file(url, output_file):
            success = True
            break

    if success:
        print()
        print("=" * 60)
        print("Next steps:")
        print("=" * 60)
        print(f"Extract the archive:")
        print(f"  cd {script_dir}")
        print(f"  tar -xf {GODOT_FILENAME}")
        print()
        print("Run the headless editor:")
        print(f"  ./{GODOT_FILENAME.replace('.tar.xz', '')} --headless")
        return 0
    else:
        print()
        print("✗ Download failed from all mirrors")
        print()
        print("Try downloading manually from:")
        for mirror_base in MIRRORS:
            print(f"  - {mirror_base}{GODOT_FILENAME}")
        print()
        print("Or download from the official site:")
        print("  https://godotengine.org/download/linux/")
        return 1

if __name__ == "__main__":
    sys.exit(main())
