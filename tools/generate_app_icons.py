#!/usr/bin/env python3
"""Resize the approved Mishkat artwork with macOS sips; verify shipped PNGs."""

import argparse
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile


APP_ROOT = Path(__file__).resolve().parents[1]
MASTER = APP_ROOT / "design/branding/mishkat-icon-master.png"


def png_info(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError(f"Not a PNG: {path}")
    width, height, depth, color = struct.unpack(">IIBB", data[16:26])
    # Use only opaque truecolor PNGs, including the App Store artwork.
    if depth != 8 or color != 2:
        raise ValueError(f"Expected opaque 8-bit RGB PNG: {path}")
    offset = 8
    while offset < len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk = data[offset + 4 : offset + 8]
        if chunk == b"tRNS":
            raise ValueError(f"Unexpected PNG transparency: {path}")
        offset += length + 12
    return width, height


def catalog_icons(catalog):
    images = json.loads((catalog / "Contents.json").read_text())["images"]
    for entry in images:
        if "filename" not in entry:
            continue
        width, height = map(float, entry["size"].split("x"))
        scale = float(entry.get("scale", "1x").removesuffix("x"))
        pixels = width * scale
        if width != height or not pixels.is_integer():
            raise ValueError(f"Unsupported icon dimensions: {entry}")
        yield catalog / entry["filename"], int(pixels)


def icon_targets(legacy_root):
    targets = {APP_ROOT / "assets/icons/icon-512.png": 512}
    targets[APP_ROOT / "android/app/src/main/res/drawable-nodpi/ic_mishkat_large.png"] = 256
    for density, size in zip(
        ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"), (48, 72, 96, 144, 192)
    ):
        path = f"android/app/src/main/res/mipmap-{density}/ic_launcher.png"
        targets[APP_ROOT / path] = size
    for platform in ("ios", "macos"):
        catalog = APP_ROOT / platform / "Runner/Assets.xcassets/AppIcon.appiconset"
        targets.update(catalog_icons(catalog))
    for size in (192, 512):
        for name in (f"Icon-{size}.png", f"Icon-maskable-{size}.png"):
            targets[APP_ROOT / "web/icons" / name] = size
    targets[APP_ROOT / "web/favicon.png"] = 32
    if legacy_root:
        legacy_root = legacy_root.resolve()
        for size in (180, 192, 512):
            targets[legacy_root / f"icons/icon-{size}.png"] = size
        targets[legacy_root / "icons/icon-maskable.png"] = 512
        catalog = legacy_root / "ios/Mishkat/Assets.xcassets/AppIcon.appiconset"
        targets.update(catalog_icons(catalog))
    return targets


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate without writing")
    parser.add_argument("--legacy-root", type=Path, help="Also update the legacy web/iOS project")
    args = parser.parse_args()
    width, height = png_info(MASTER)
    if width != height or width < 1024:
        parser.error("Master artwork must be square and at least 1024 pixels")
    targets = icon_targets(args.legacy_root)
    if not args.check:
        sips = shutil.which("sips")
        if not sips:
            parser.error("Generating icons requires macOS sips; --check works anywhere")
        # Produce each size once, directly from the original, without cumulative resizing.
        with tempfile.TemporaryDirectory(prefix="mishkat-icons-") as temp:
            for size in sorted(set(targets.values())):
                output = Path(temp) / f"{size}.png"
                subprocess.run(
                    [sips, "--resampleHeightWidth", str(size), str(size), str(MASTER), "--out", str(output)],
                    check=True, capture_output=True, text=True,
                )
                if png_info(output) != (size, size):
                    raise ValueError(f"Incorrect generated dimensions: {output}")
            for path, size in targets.items():
                path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(Path(temp) / f"{size}.png", path)
    for path, size in targets.items():
        actual = png_info(path)
        if actual != (size, size):
            raise ValueError(f"{path}: expected {size} × {size}, got {actual}")
    print(f"Verified {len(targets)} opaque RGB icons and {width} × {height} master artwork.")


if __name__ == "__main__":
    main()
